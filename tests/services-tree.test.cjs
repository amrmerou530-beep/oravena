const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const path=require('node:path');

const root=path.resolve(__dirname,'..');
const source=fs.readFileSync(path.join(root,'dashboard.js'),'utf8');
const css=fs.readFileSync(path.join(root,'dashboard.css'),'utf8');

test('service tree derives children and counts from the stored parent relationship',()=>{
  const functionSource=source.match(/function serviceTreeData\(\)\{[\s\S]*?\n\}/)?.[0];
  assert.ok(functionSource,'serviceTreeData must exist');
  const context={db:{services:[
    {id:'root-b',nameAr:'ب',serviceType:'رئيسية',sortOrder:'2'},
    {id:'child-1',nameAr:'فرع 1',serviceType:'فرعية',parentServiceId:'root-a'},
    {id:'root-a',nameAr:'أ',serviceType:'رئيسية',sortOrder:'1'},
    {id:'child-2',nameAr:'فرع 2',serviceType:'فرعية',parentServiceId:'root-a'},
    {id:'orphan',nameAr:'يتيم',serviceType:'فرعية',parentServiceId:'missing'}
  ]}};
  vm.createContext(context);vm.runInContext(`${functionSource};result=serviceTreeData()`,context);
  assert.deepEqual(Array.from(context.result,row=>[row.id,row.children.length]),[['root-a',2],['root-b',0]]);
});

test('services rendering stays isolated and retains existing CRUD hooks',()=>{
  assert.match(source,/if\(k==='services'\)return servicesTreePage\(\)/);
  assert.match(source,/data-edit="services:\$\{service\.id\}"/);
  assert.match(source,/data-delete="services:\$\{service\.id\}"/);
  assert.match(source,/parentServiceId/);
  assert.match(source,/drawServiceTreeLines/);
  assert.match(css,/\.orv-svc-tree/);
  assert.match(css,/\.orv-svc-tree-lines path/);
});
