#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '../..');
const { documentStart, applyAfterLoad } = require('../../lib/ios-admin-portrait-scripts');
const outDir = path.join(root, 'ios-admin', 'CloudStoreAdmin', 'Resources');

fs.mkdirSync(outDir, { recursive: true });
fs.writeFileSync(path.join(outDir, 'portrait-document-start.js'), `${documentStart}\n`);
fs.writeFileSync(path.join(outDir, 'portrait-apply-after-load.js'), `${applyAfterLoad}\n`);
console.log('Synced ios-admin portrait scripts to CloudStoreAdmin/Resources/');
