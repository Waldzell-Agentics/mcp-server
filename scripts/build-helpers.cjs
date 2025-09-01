// Cross-platform build helper script
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

// Create directory recursively (cross-platform equivalent of mkdir -p)
function mkdirp(dirPath) {
  const absolutePath = path.resolve(dirPath);
  if (!fs.existsSync(absolutePath)) {
    fs.mkdirSync(absolutePath, { recursive: true });
  }
}

// Create ESM package.json
function createEsmPackage() {
  mkdirp('dist/esm');
  fs.writeFileSync('dist/esm/package.json', JSON.stringify({ type: 'module' }, null, 2));
}

// Create CJS package.json
function createCjsPackage() {
  mkdirp('dist/cjs');
  fs.writeFileSync('dist/cjs/package.json', JSON.stringify({ type: 'commonjs' }, null, 2));
}

// Generate version info with performance optimizations and git-free fallback
function generateVersion() {
  mkdirp('dist');
  
  // Check if version.json already exists and use cached version for performance
  const versionPath = 'dist/version.json';
  if (fs.existsSync(versionPath) && process.env.DOCKER_BUILD) {
    console.log('Using cached version.json for Docker build');
    return;
  }
  
  // Default version info for environments without git or during Docker builds
  let versionInfo = {
    sha: process.env.GIT_SHA || 'build',
    tag: process.env.GIT_TAG || 'v' + (process.env.npm_package_version || '0.3.0'),
    branch: process.env.GIT_BRANCH || 'main',
    version: process.env.npm_package_version || '0.3.0'
  };
  
  // Only attempt git operations if not in Docker/CI and git is available
  if (!process.env.DOCKER_BUILD && !process.env.CI) {
    try {
      // Check if git is available and we're in a git repository
      const gitAvailable = fs.existsSync('.git') || fs.existsSync('../.git');
      
      if (gitAvailable) {
        try {
          versionInfo.sha = execSync('git rev-parse HEAD 2>/dev/null', { encoding: 'utf8', timeout: 5000 }).trim();
        } catch {}
        
        try {
          versionInfo.tag = execSync('git describe --tags --always 2>/dev/null', { encoding: 'utf8', timeout: 5000 }).trim();
        } catch {}
        
        try {
          versionInfo.branch = execSync('git rev-parse --abbrev-ref HEAD 2>/dev/null', { encoding: 'utf8', timeout: 5000 }).trim();
        } catch {}
      }
    } catch (error) {
      // Silently fall back to default values
      console.warn('Git not available, using fallback version info');
    }
  }
  
  fs.writeFileSync(versionPath, JSON.stringify(versionInfo, null, 2));
  console.log(`Generated version info: ${JSON.stringify(versionInfo)}`);
}

// Process command line arguments
const command = process.argv[2];

switch (command) {
  case 'esm-package':
    createEsmPackage();
    break;
  case 'cjs-package':
    createCjsPackage();
    break;
  case 'generate-version':
    generateVersion();
    break;
  default:
    console.error('Unknown command:', command);
    process.exit(1);
}
