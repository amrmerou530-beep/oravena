const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const vm=require('node:vm');

const root=path.resolve(__dirname,'..');
const html=fs.readFileSync(path.join(root,'about.html'),'utf8');
const js=fs.readFileSync(path.join(root,'about.js'),'utf8');
const css=fs.readFileSync(path.join(root,'story.css'),'utf8');

test('cinematic story contains six real scenes, six controls and six local assets',()=>{
  assert.equal((html.match(/data-story-scene=/g)||[]).length,6);
  assert.equal((html.match(/data-story-go=/g)||[]).length,6);
  for(let index=1;index<=6;index++){
    const prefix=String(index).padStart(2,'0');
    const match=html.match(new RegExp(`assets/story/${prefix}-[^"']+\\.webp`));
    assert.ok(match,`missing image reference for scene ${prefix}`);
    assert.ok(fs.statSync(path.join(root,match[0])).size>30000,`scene ${prefix} image is empty`);
  }
});

test('every translated story key exists in Arabic, Turkish and English',()=>{
  const copySource=js.slice(0,js.indexOf('const root='));
  const context={};vm.createContext(context);vm.runInContext(`${copySource};result=copy`,context);
  const keys=[...html.matchAll(/data-i18n="([^"]+)"/g)].map(match=>match[1]);
  for(const language of ['ar','tr','en'])for(const key of keys)assert.ok(context.result[language][key]!==undefined,`${language}.${key} is missing`);
});

test('story motion is native, isolated and keeps the original navigation contract',()=>{
  assert.match(js,/requestAnimationFrame\(renderStory\)/);
  assert.match(js,/data-story-progress-line/);
  assert.match(css,/\.orv-story-scene/);
  assert.match(css,/@media\(max-width:680px\)/);
  assert.match(css,/@media\(prefers-reduced-motion:reduce\)/);
  assert.doesNotMatch(html,/https:\/\/.*(?:gsap|cdn)/i);
  assert.match(html,/class="topbar story-topbar"/);
  assert.match(html,/<footer>/);
});
