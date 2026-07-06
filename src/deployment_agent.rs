use hbb_common::{config::Config, log};
use reqwest;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::Path;
use std::time::Duration;
use tokio::io::AsyncWriteExt;
use tokio::time::sleep;

#[derive(Deserialize, Clone)]
struct JobInfo {
	job_id: i32,
	job_name: String,
	package_id: i32,
	package_name: String,
	version: String,
	file_name: String,
	sha256: String,
	download_url: String,
	install_command: String,
	uninstall_command: Option<String>,
	timeout_seconds: u64,
	reboot_policy: String,
	pre_check_reg_key: Option<String>,
	pre_check_reg_value: Option<String>,
	pre_check_reg_type: Option<String>,
	pre_check_reg_compare: Option<String>,
	pre_check_reg_expected: Option<String>,
}

#[derive(Serialize)]
struct HeartbeatForm {
	device_id: String,
	uuid: String,
	agent_version: String,
	os: String,
	hostname: String,
	ip_address: String,
}

#[derive(Serialize)]
struct StatusUpdateForm {
	device_id: String,
	uuid: String,
	status: String,
	exit_code: i32,
	message: String,
	need_reboot: bool,
}

#[derive(Serialize)]
struct LogForm {
	device_id: String,
	uuid: String,
	log_type: String,
	content: String,
}

// Convert bytes to hex string manually without external hex crate
fn to_hex_string(bytes: &[u8]) -> String {
	bytes.iter().map(|b| format!("{:02x}", b)).collect()
}

#[cfg(windows)]
fn check_prerequisites(job: &JobInfo) -> bool {
	let reg_key = match &job.pre_check_reg_key {
		Some(k) => k,
		None => return false,
	};
	if reg_key.is_empty() {
		return false;
	}

	let reg_value = job.pre_check_reg_value.as_deref().unwrap_or("");
	let reg_type = job.pre_check_reg_type.as_deref().unwrap_or("exists");
	let reg_compare = job.pre_check_reg_compare.as_deref().unwrap_or("exists");
	let reg_expected = job.pre_check_reg_expected.as_deref().unwrap_or("");

	use winreg::{enums::*, RegKey};
	let hklm = RegKey::predef(HKEY_LOCAL_MACHINE);
	let key = match hklm.open_subkey(reg_key) {
		Ok(k) => k,
		Err(_) => return false, // Key doesn't exist
	};

	if reg_compare == "exists" && reg_value.is_empty() {
		return true; // Key exists, match!
	}

	match reg_type {
		"exists" => {
			key.get_raw_value(reg_value).is_ok()
		}
		"dword" => {
			let val: u32 = match key.get_value(reg_value) {
				Ok(v) => v,
				Err(_) => return false,
			};
			let expected_val: u32 = reg_expected.parse().unwrap_or(0);
			match reg_compare {
				"eq" => val == expected_val,
				"ne" => val != expected_val,
				"gt" => val > expected_val,
				"gte" => val >= expected_val,
				"lt" => val < expected_val,
				"lte" => val <= expected_val,
				_ => false,
			}
		}
		"sz" => {
			let val: String = match key.get_value(reg_value) {
				Ok(v) => v,
				Err(_) => return false,
			};
			match reg_compare {
				"eq" => val == reg_expected,
				"ne" => val != reg_expected,
				_ => false,
			}
		}
		_ => false,
	}
}

#[cfg(not(windows))]
fn check_prerequisites(_job: &JobInfo) -> bool {
	false
}

pub async fn start_agent() {
	log::info!("Starting Software Deployment Agent background thread...");

	// 1. Start heartbeat loop
	tokio::spawn(async move {
		loop {
			if let Err(e) = send_heartbeat().await {
				log::error!("Agent heartbeat failed: {:?}", e);
			}
			sleep(Duration::from_secs(60)).await;
		}
	});

	// 2. Start jobs polling loop
	loop {
		if let Err(e) = poll_jobs().await {
			log::error!("Agent polling failed: {:?}", e);
		}
		sleep(Duration::from_secs(30)).await;
	}
}

fn get_clean_server_url() -> String {
	let mut server_url = crate::ui_interface::get_api_server();
	if server_url.is_empty() {
		return "".to_owned();
	}
	if !server_url.starts_with("http://") && !server_url.starts_with("https://") {
		server_url = format!("http://{}", server_url);
	}
	// Trim trailing slashes
	server_url.trim_end_matches('/').to_owned()
}

async fn send_heartbeat() -> hbb_common::ResultType<()> {
	let server_url = get_clean_server_url();
	if server_url.is_empty() {
		return Ok(());
	}

	let device_id = Config::get_id();
	let uuid = crate::ui_interface::get_uuid();
	let hostname = crate::common::hostname();
	let os = std::env::consts::OS.to_string();

	let url = format!("{}/api/agent/deployment/heartbeat", server_url);
	let form = HeartbeatForm {
		device_id,
		uuid,
		agent_version: crate::VERSION.to_string(),
		os,
		hostname,
		ip_address: "".to_string(), // Server will auto-detect from remote IP if empty
	};

	let client = reqwest::Client::new();
	let mut req = client.post(&url).json(&form);

	if let Ok(token) = std::env::var("DEPLOYMENT_AGENT_TOKEN") {
		req = req.header("X-Agent-Token", token);
	}

	req.send().await?;
	Ok(())
}

async fn poll_jobs() -> hbb_common::ResultType<()> {
	let server_url = get_clean_server_url();
	if server_url.is_empty() {
		return Ok(());
	}

	let device_id = Config::get_id();
	let uuid = crate::ui_interface::get_uuid();

	let url = format!(
		"{}/api/agent/deployment/jobs?device_id={}&uuid={}",
		server_url, device_id, uuid
	);

	let client = reqwest::Client::new();
	let mut req = client.get(&url);

	if let Ok(token) = std::env::var("DEPLOYMENT_AGENT_TOKEN") {
		req = req.header("X-Agent-Token", token);
	}

	let resp = req.send().await?;
	if !resp.status().is_success() {
		return Ok(());
	}

	let jobs: Vec<JobInfo> = resp.json().await?;
	for job in jobs {
		log::info!(
			"Processing deployment job: {} (ID: {}) for package: {}",
			job.job_name,
			job.job_id,
			job.package_name
		);

		if let Err(e) = execute_job(&job, &server_url, &device_id, &uuid).await {
			log::error!("Failed to execute job {}: {:?}", job.job_id, e);
		}
	}

	Ok(())
}

async fn update_status(
	server_url: &str,
	job_id: i32,
	device_id: &str,
	uuid: &str,
	status: &str,
	exit_code: i32,
	message: &str,
	need_reboot: bool,
) -> hbb_common::ResultType<()> {
	let url = format!("{}/api/agent/deployment/jobs/{}/status", server_url, job_id);
	let form = StatusUpdateForm {
		device_id: device_id.to_string(),
		uuid: uuid.to_string(),
		status: status.to_string(),
		exit_code,
		message: message.to_string(),
		need_reboot,
	};

	let client = reqwest::Client::new();
	let mut req = client.post(&url).json(&form);

	if let Ok(token) = std::env::var("DEPLOYMENT_AGENT_TOKEN") {
		req = req.header("X-Agent-Token", token);
	}

	req.send().await?;
	Ok(())
}

async fn send_log(
	server_url: &str,
	job_id: i32,
	device_id: &str,
	uuid: &str,
	log_type: &str,
	content: &str,
) -> hbb_common::ResultType<()> {
	let url = format!("{}/api/agent/deployment/jobs/{}/log", server_url, job_id);
	let form = LogForm {
		device_id: device_id.to_string(),
		uuid: uuid.to_string(),
		log_type: log_type.to_string(),
		content: content.to_string(),
	};

	let client = reqwest::Client::new();
	let mut req = client.post(&url).json(&form);

	if let Ok(token) = std::env::var("DEPLOYMENT_AGENT_TOKEN") {
		req = req.header("X-Agent-Token", token);
	}

	req.send().await?;
	Ok(())
}

async fn compute_sha256(path: &Path) -> hbb_common::ResultType<String> {
	use sha2::{Digest, Sha256};
	use tokio::io::AsyncReadExt;

	let mut file = tokio::fs::File::open(path).await?;
	let mut hasher = Sha256::new();
	let mut buffer = [0; 8192];

	loop {
		let n = file.read(&mut buffer).await?;
		if n == 0 {
			break;
		}
		hasher.update(&buffer[..n]);
	}

	Ok(to_hex_string(&hasher.finalize()))
}

async fn execute_job(
	job: &JobInfo,
	server_url: &str,
	device_id: &str,
	uuid: &str,
) -> hbb_common::ResultType<()> {
	// 1. Dynamic prerequisite check
	if check_prerequisites(job) {
		log::info!(
			"Prerequisites satisfied for package {}. Skipping download/install.",
			job.package_name
		);
		update_status(
			server_url,
			job.job_id,
			device_id,
			uuid,
			"success",
			0,
			"Already Installed (Skipped by pre-requisite registry check)",
			false,
		)
		.await?;
		return Ok(());
	}

	// 2. Download package
	update_status(
		server_url,
		job.job_id,
		device_id,
		uuid,
		"downloading",
		0,
		"Downloading package installer...",
		false,
	)
	.await?;

	let temp_dir = std::env::temp_dir();
	let target_path = temp_dir.join(&job.file_name);

	if target_path.exists() {
		let _ = std::fs::remove_file(&target_path);
	}

	let client = reqwest::Client::new();
	let mut req = client.get(&job.download_url);
	if let Ok(token) = std::env::var("DEPLOYMENT_AGENT_TOKEN") {
		req = req.header("X-Agent-Token", token);
	}

	let mut download_resp = req.send().await?;
	if !download_resp.status().is_success() {
		let err_msg = format!("Download failed with status: {}", download_resp.status());
		update_status(
			server_url,
			job.job_id,
			device_id,
			uuid,
			"failed",
			-1,
			&err_msg,
			false,
		)
		.await?;
		return Ok(());
	}

	let mut file = tokio::fs::File::create(&target_path).await?;
	while let Some(chunk) = download_resp.chunk().await? {
		file.write_all(&chunk).await?;
	}
	file.flush().await?;

	// 3. Verify Checksum
	update_status(
		server_url,
		job.job_id,
		device_id,
		uuid,
		"downloading",
		0,
		"Verifying SHA256 checksum...",
		false,
	)
	.await?;

	let computed_sha = compute_sha256(&target_path).await?;
	if computed_sha != job.sha256 {
		let msg = format!(
			"SHA256 verification failed. Expected {}, got {}",
			job.sha256, computed_sha
		);
		log::error!("{}", msg);
		update_status(
			server_url,
			job.job_id,
			device_id,
			uuid,
			"failed",
			-1,
			&msg,
			false,
		)
		.await?;
		let _ = std::fs::remove_file(&target_path);
		return Ok(());
	}

	// 4. Run silent install
	update_status(
		server_url,
		job.job_id,
		device_id,
		uuid,
		"installing",
		0,
		"Executing silent installation...",
		false,
	)
	.await?;

	#[cfg(target_os = "windows")]
	let mut cmd = tokio::process::Command::new("cmd");
	#[cfg(target_os = "windows")]
	cmd.args(&["/C", &job.install_command]);

	#[cfg(not(target_os = "windows"))]
	let mut cmd = tokio::process::Command::new("sh");
	#[cfg(not(target_os = "windows"))]
	cmd.args(&["-c", &job.install_command]);

	cmd.current_dir(&temp_dir)
		.kill_on_drop(true)
		.stdout(std::process::Stdio::piped())
		.stderr(std::process::Stdio::piped());

	let child = cmd.spawn()?;

	let wait_res = tokio::time::timeout(
		Duration::from_secs(job.timeout_seconds),
		child.wait_with_output(),
	)
	.await;

	match wait_res {
		Ok(Ok(output)) => {
			let exit_code = output.status.code().unwrap_or(-1);
			let stdout_str = String::from_utf8_lossy(&output.stdout).to_string();
			let stderr_str = String::from_utf8_lossy(&output.stderr).to_string();

			// Send logs
			if !stdout_str.is_empty() {
				send_log(
					server_url,
					job.job_id,
					device_id,
					uuid,
					"stdout",
					&stdout_str,
				)
				.await
				.ok();
			}
			if !stderr_str.is_empty() {
				send_log(
					server_url,
					job.job_id,
					device_id,
					uuid,
					"stderr",
					&stderr_str,
				)
				.await
				.ok();
			}

			if exit_code == 0 {
				update_status(
					server_url,
					job.job_id,
					device_id,
					uuid,
					"success",
					0,
					"Installation completed successfully.",
					false,
				)
				.await?;
			} else if exit_code == 3010 {
				// Windows pending reboot code
				update_status(
					server_url,
					job.job_id,
					device_id,
					uuid,
					"need_reboot",
					3010,
					"Installation finished successfully. Reboot is required.",
					true,
				)
				.await?;
			} else {
				let err_msg = format!("Installation failed with exit code {}", exit_code);
				update_status(
					server_url,
					job.job_id,
					device_id,
					uuid,
					"failed",
					exit_code,
					&err_msg,
					false,
				)
				.await?;
			}
		}
		Ok(Err(e)) => {
			let err_msg = format!("Process wait error: {:?}", e);
			update_status(
				server_url,
				job.job_id,
				device_id,
				uuid,
				"failed",
				-1,
				&err_msg,
				false,
			)
			.await?;
		}
		Err(_) => {
			let err_msg = format!(
				"Installation process timed out after {} seconds.",
				job.timeout_seconds
			);
			update_status(
				server_url,
				job.job_id,
				device_id,
				uuid,
				"failed",
				-1,
				&err_msg,
				false,
			)
			.await?;
		}
	}

	// Clean up file
	let _ = std::fs::remove_file(&target_path);
	Ok(())
}
