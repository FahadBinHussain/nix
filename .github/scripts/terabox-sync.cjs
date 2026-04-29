const path = require('path');

function fail(message) {
  console.error(message);
  process.exit(1);
}

function normalizeRemoteDir(input) {
  if (!input || input.trim() === '') {
    return '/nix';
  }

  let remote = input.trim();
  if (!remote.startsWith('/')) {
    remote = `/${remote}`;
  }

  if (remote.length > 1) {
    remote = remote.replace(/\/+$/, '');
  }

  return remote;
}

async function main() {
  const uploaderModulePath = process.env.TERABOX_UPLOAD_TOOL_PATH;
  if (!uploaderModulePath) {
    fail('TERABOX_UPLOAD_TOOL_PATH is missing.');
  }

  // eslint-disable-next-line import/no-dynamic-require, global-require
  const TeraboxUploader = require(uploaderModulePath);

  const localFile = process.env.FILE_NAME;
  if (!localFile) {
    fail('FILE_NAME is missing.');
  }

  const remoteDir = normalizeRemoteDir(process.env.TERABOX_REMOTE_DIR);
  const remoteFileName = path.basename(localFile);
  const credentials = {
    ndus: process.env.TERABOX_NDUS,
    jsToken: process.env.TERABOX_JSTOKEN,
    appId: process.env.TERABOX_APP_ID || '250528',
    bdstoken: process.env.TERABOX_BDSTOKEN || '',
    browserId: process.env.TERABOX_BROWSER_ID || '',
  };

  if (!credentials.ndus || !credentials.jsToken) {
    fail('TERABOX_NDUS and TERABOX_JSTOKEN are required.');
  }

  const uploader = new TeraboxUploader(credentials);

  let listResult = await uploader.fetchFileList(remoteDir);
  if (!listResult.success && remoteDir !== '/') {
    console.log(`TeraBox folder ${remoteDir} was not readable yet. Trying to create it...`);
    const createResult = await uploader.createDirectory(remoteDir);
    if (!createResult.success) {
      console.log(`TeraBox create directory response: ${JSON.stringify(createResult)}`);
    }
    listResult = await uploader.fetchFileList(remoteDir);
  }

  if (!listResult.success) {
    fail(`TeraBox file list failed: ${JSON.stringify(listResult)}`);
  }

  const files = Array.isArray(listResult.data?.list) ? listResult.data.list : [];
  const existing = files.find((entry) => {
    const serverName = typeof entry.server_filename === 'string' ? entry.server_filename : '';
    const entryPath = typeof entry.path === 'string' ? entry.path : '';
    return serverName === remoteFileName || entryPath.endsWith(`/${remoteFileName}`);
  });

  if (existing) {
    console.log('File already exists in TeraBox. Skipping upload.');
    return;
  }

  if (files.length >= 100) {
    console.log('Warning: TeraBox list returned 100 entries. Duplicate checks only cover the first page.');
  }

  let lastLoggedPercent = -10;
  const uploadResult = await uploader.uploadFile(localFile, (loaded, total) => {
    if (!total || total <= 0) {
      return;
    }

    const percent = Math.floor((loaded / total) * 100);
    if (percent >= lastLoggedPercent + 10 || percent === 100) {
      lastLoggedPercent = percent;
      console.log(`TeraBox upload progress: ${percent}%`);
    }
  }, remoteDir);

  if (!uploadResult.success) {
    fail(`TeraBox upload failed: ${JSON.stringify(uploadResult)}`);
  }

  console.log('TeraBox Upload Complete!');
  if (uploadResult.fileDetails) {
    console.log(JSON.stringify(uploadResult.fileDetails));
  }
}

main().catch((error) => {
  fail(`TeraBox sync crashed: ${error.stack || error.message}`);
});
