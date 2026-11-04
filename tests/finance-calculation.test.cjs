const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const path=require('node:path');

const source=fs.readFileSync(path.join(__dirname,'..','dashboard.js'),'utf8');
const match=source.match(/function sessionFinancials\(record=\{\}\)\{[\s\S]*?\n\}/);
assert.ok(match,'sessionFinancials must exist');
const context={};
vm.runInNewContext(`${match[0]};this.calculate=sessionFinancials`,context);

const result=context.calculate({amount:3000,paidAmount:1800,splitMode:'نسبة مئوية',clinicPercent:60});
assert.equal(result.clinicShare,1800);
assert.equal(result.doctorShare,1200);
assert.equal(result.clinicCollected,1080);
assert.equal(result.doctorCollected,720);
assert.equal(result.clinicOutstanding,720);
assert.equal(result.doctorOutstanding,480);
assert.equal(result.remainingAmount,1200);

const complete=context.calculate({amount:3000,paidAmount:3000,splitMode:'مبالغ ثابتة',clinicShare:1800,doctorShare:1200});
assert.equal(complete.clinicCollected,1800);
assert.equal(complete.doctorCollected,1200);
assert.equal(complete.remainingAmount,0);

const discounted=context.calculate({amount:3000,discountPercent:10,paidAmount:1700,splitMode:'نسبة مئوية',clinicPercent:60});
assert.equal(discounted.grossAmount,3000);
assert.equal(discounted.discountAmount,300);
assert.equal(discounted.amount,2700);
assert.equal(discounted.remainingAmount,1000);
assert.equal(discounted.clinicShare,1620);
assert.equal(discounted.doctorShare,1080);

console.log('PASS: partial payment is distributed proportionally and outstanding shares remain visible');
