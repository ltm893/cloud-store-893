'use strict';

const { test, before } = require('node:test');
const assert = require('node:assert/strict');
const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const { documentStart, applyAfterLoad } = require('../lib/ios-admin-portrait-scripts');

const resourcesDir = path.join(
  __dirname,
  '..',
  'ios-admin',
  'CloudStoreAdmin',
  'Resources',
);

function readResource(name) {
  return fs.readFileSync(path.join(resourcesDir, name), 'utf8').trim();
}

function createDom() {
  const htmlClasses = new Set();
  const bodyClasses = new Set(['admin-landscape']);
  let blocker = { id: 'portraitBlocker', parent: null, removed: false };
  const styles = [];

  const documentElement = {
    classList: {
      add: (c) => htmlClasses.add(c),
      contains: (c) => htmlClasses.has(c),
    },
    appendChild(node) {
      if (node.tagName === 'style') styles.push(node);
    },
  };

  const body = {
    classList: {
      remove: (c) => bodyClasses.delete(c),
      contains: (c) => bodyClasses.has(c),
    },
  };

  const document = {
    documentElement,
    body,
    getElementById(id) {
      if (id === 'portraitBlocker' && !blocker.removed) return blocker;
      if (id === 'cloudstore-ios-portrait-style') {
        return styles.find((s) => s.id === 'cloudstore-ios-portrait-style') || null;
      }
      return null;
    },
    createElement(tag) {
      return {
        tagName: tag,
        id: '',
        textContent: '',
      };
    },
    head: { appendChild(node) { styles.push(node); } },
  };

  blocker.remove = () => {
    blocker.removed = true;
  };

  return {
    document,
    htmlClasses,
    bodyClasses,
    styles,
    get blocker() {
      return blocker.removed ? null : blocker;
    },
  };
}

function runScript(source, dom) {
  const orientationLockCalls = [];
  const context = {
    window: { __cloudstoreIosPortrait: false },
    document: dom.document,
    screen: {
      orientation: {
        lock: (...args) => {
          orientationLockCalls.push(args);
          return Promise.resolve();
        },
      },
    },
  };
  vm.createContext(context);
  vm.runInContext(source, context);
  return { context, orientationLockCalls };
}

before(() => {
  execSync('node scripts/sync-ios-portrait-resources.js', {
    cwd: path.join(__dirname, '..'),
    stdio: 'pipe',
  });
});

test('bundled Resources match lib/ios-admin-portrait-scripts.js', () => {
  assert.equal(readResource('portrait-document-start.js'), documentStart);
  assert.equal(readResource('portrait-apply-after-load.js'), applyAfterLoad);
});

test('documentStart injects portrait CSS and noops orientation.lock', async () => {
  const dom = createDom();
  const { context } = runScript(documentStart, dom);

  assert.equal(context.window.__cloudstoreIosPortrait, true);
  assert.ok(dom.htmlClasses.has('admin-portrait-ok'));
  assert.equal(dom.styles.length, 1);
  assert.match(dom.styles[0].textContent, /portrait-blocker.*display: none !important/);

  await context.screen.orientation.lock('landscape');
});

test('documentStart is idempotent', () => {
  const dom = createDom();
  runScript(documentStart, dom);
  runScript(documentStart, dom);
  assert.equal(dom.styles.length, 1);
});

test('applyAfterLoad removes landscape class and portrait blocker', () => {
  const dom = createDom();
  runScript(applyAfterLoad, dom);

  assert.ok(dom.htmlClasses.has('admin-portrait-ok'));
  assert.equal(dom.bodyClasses.has('admin-landscape'), false);
  assert.equal(dom.blocker, null);
});
