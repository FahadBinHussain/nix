import fs from "node:fs";
import path from "node:path";

function fail(message, details) {
  console.error(message);
  if (details) {
    console.error(details);
  }
  process.exit(1);
}

function getArg(name, fallback = undefined) {
  const prefix = `--${name}=`;
  const inline = process.argv.find((arg) => arg.startsWith(prefix));
  if (inline) {
    return inline.slice(prefix.length);
  }

  const index = process.argv.indexOf(`--${name}`);
  if (index !== -1 && index + 1 < process.argv.length) {
    return process.argv[index + 1];
  }

  return fallback;
}

function hasFlag(name) {
  return process.argv.includes(`--${name}`);
}

function extractAuth(json) {
  const token = [
    json?.access_token,
    json?.token,
    json?.data?.access_token,
    json?.data?.token,
    json?.response?.access_token,
    json?.response?.token,
  ].find(Boolean);

  const accountId = [
    json?.account_id,
    json?.acc_id,
    json?.user_id,
    json?.data?.account_id,
    json?.data?.acc_id,
    json?.data?.user_id,
    json?.response?.account_id,
    json?.response?.acc_id,
    json?.response?.user_id,
  ].find(Boolean);

  if (json?._status !== "success" || !token || !accountId) {
    fail("uDrop auth did not succeed.", JSON.stringify(json));
  }

  return {
    token: String(token).trim(),
    accountId: String(accountId).trim(),
  };
}

async function postForm(url, params, timeoutMs) {
  const body = new URLSearchParams();
  for (const [key, value] of Object.entries(params)) {
    if (value !== undefined && value !== null && value !== "") {
      body.set(key, String(value));
    }
  }

  const response = await fetch(url, {
    method: "POST",
    body,
    signal: AbortSignal.timeout(timeoutMs),
  });

  const text = await response.text();
  if (!response.ok) {
    fail(`HTTP ${response.status} from ${url}`, text);
  }

  try {
    return JSON.parse(text);
  } catch {
    fail(`Non-JSON response from ${url}`, text);
  }
}

async function main() {
  const filePath = getArg("file");
  if (!filePath) {
    fail("Provide --file <path>.");
  }

  const key1 = getArg("key1", process.env.UDROP_KEY1);
  const key2 = getArg("key2", process.env.UDROP_KEY2);
  const folderId = getArg("folder-id", process.env.UDROP_FOLDER_ID);
  const timeoutSec = Number(getArg("timeout-sec", "30"));
  const forceUpload = hasFlag("force-upload");

  if (!key1 || !key2) {
    fail("Provide UDROP_KEY1 and UDROP_KEY2 via env vars or --key1/--key2.");
  }

  const resolvedFilePath = path.resolve(filePath);
  if (!fs.existsSync(resolvedFilePath)) {
    fail(`File not found: ${resolvedFilePath}`);
  }

  const fileName = path.basename(resolvedFilePath);
  const timeoutMs = timeoutSec * 1000;

  console.log(`Testing uDrop upload for ${fileName}`);
  console.log(`Timeout: ${timeoutSec} seconds`);
  console.log(`Folder ID: ${folderId || "<root>"}`);

  console.log("Calling uDrop authorize...");
  const authJson = await postForm("https://www.udrop.com/api/v2/authorize", {
    key1,
    key2,
  }, timeoutMs);
  const auth = extractAuth(authJson);
  console.log("uDrop auth succeeded.");
  console.log(`Account ID: ${auth.accountId}`);

  console.log("Listing target folder...");
  const listJson = await postForm("https://www.udrop.com/api/v2/folder/listing", {
    access_token: auth.token,
    account_id: auth.accountId,
    parent_folder_id: folderId,
  }, timeoutMs);

  const files = Array.isArray(listJson?.data?.files) ? listJson.data.files : [];
  const existing = files.find((entry) => entry?.filename === fileName);
  if (existing && !forceUpload) {
    console.log("File already exists on uDrop. Skipping upload.");
    console.log(JSON.stringify(existing));
    return;
  }

  if (existing && forceUpload) {
    console.log("File already exists on uDrop, but --force-upload was supplied.");
  }

  console.log("Uploading via Node fetch/FormData...");
  const form = new FormData();
  form.set("access_token", auth.token);
  form.set("account_id", auth.accountId);
  if (folderId) {
    form.set("folder_id", folderId);
  }
  form.set(
    "upload_file",
    await fs.openAsBlob(resolvedFilePath),
    fileName,
  );

  const uploadResponse = await fetch("https://www.udrop.com/api/v2/file/upload", {
    method: "POST",
    body: form,
    signal: AbortSignal.timeout(Math.max(timeoutMs, 300000)),
  });

  const uploadText = await uploadResponse.text();
  if (!uploadResponse.ok) {
    fail(`HTTP ${uploadResponse.status} from uDrop upload`, uploadText);
  }

  let uploadJson;
  try {
    uploadJson = JSON.parse(uploadText);
  } catch {
    fail("uDrop upload returned non-JSON.", uploadText);
  }

  console.log(JSON.stringify(uploadJson));
  if (uploadJson?._status === "success") {
    console.log("uDrop upload test completed successfully.");
    return;
  }

  fail("uDrop upload test completed, but the API did not report success.", JSON.stringify(uploadJson));
}

main().catch((error) => {
  fail(`uDrop Node test crashed: ${error.message}`, error.stack);
});
