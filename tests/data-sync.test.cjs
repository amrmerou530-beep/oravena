const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const path=require('node:path');

const root=path.resolve(__dirname,'..');
const clientSource=fs.readFileSync(path.join(root,'supabase-client.js'),'utf8');

class Storage{
  constructor(){this.map=new Map()}
  getItem(key){return this.map.has(key)?this.map.get(key):null}
  setItem(key,value){this.map.set(key,String(value))}
  removeItem(key){this.map.delete(key)}
}

function response(status,body){
  return {status,ok:status>=200&&status<300,json:async()=>body};
}

function device(token,accountType,server){
  const localStorage=new Storage();
  localStorage.setItem('oravena_auth_session_v1',JSON.stringify({access_token:token,refresh_token:'refresh'}));
  localStorage.setItem('oravena_account_access_v1',JSON.stringify({account_type:accountType,user_id:accountType==='patient'?'patient-user':'doctor-user'}));
  const context={
    console,localStorage,URL,URLSearchParams,
    location:{href:'https://clinic.test/system.html',assign(){}},
    history:{replaceState(){}},
    fetch:(url,options)=>server.fetch(token,url,options),
    ORAVENA_SUPABASE:{url:'https://test-project.supabase.co',anonKey:'a'.repeat(80)}
  };
  context.window=context;
  vm.runInNewContext(clientSource,context,{filename:'supabase-client.js'});
  return context.OravenaDB;
}

class MockServer{
  constructor(){
    this.patient={id:'patient-1',auth_user_id:'patient-user',file_number:'OR-1',full_name:'مريض الاختبار',email:'patient@test.local',phone:'0100000000',balance:0};
    this.appointments=[];
    this.records=[];
    this.counter=0;
  }
  body(options){return options?.body?JSON.parse(options.body):{}}
  core(token){
    const patient=token==='patient-token';
    return {
      patients:[this.patient],
      appointments:this.appointments.filter(a=>!patient||a.patient_id===this.patient.id),
      records:this.records.filter(r=>!patient||(r.patient_id===this.patient.id&&r.patient_visible)),
      staff:[],services:[{id:'svc-1',name_ar:'كشف',active:true,sort_order:1}],
      meta:{version:22,user_id:patient?'patient-user':'doctor-user'}
    };
  }
  async fetch(token,url,options={}){
    const endpoint=new URL(url).pathname;
    if(endpoint.endsWith('/oravena_persistence_health'))return response(200,{ok:true,version:22});
    if(endpoint.endsWith('/oravena_ensure_patient_account'))return response(200,this.patient.id);
    if(endpoint.endsWith('/create_appointment_request')){
      const b=this.body(options); const id=`appointment-${++this.counter}`;
      this.appointments.push({id,patient_id:this.patient.id,full_name:b.p_full_name,email:b.p_email,phone:b.p_phone,service:b.p_service,status:'new_request',appointment_date:null,appointment_time:null,doctor_name:null,created_at:'2026-10-27T10:00:00Z',updated_at:'2026-10-27T10:00:00Z'});
      return response(200,id);
    }
    if(endpoint.endsWith('/oravena_core_data'))return response(200,this.core(token));
    if(endpoint.endsWith('/oravena_save_appointment')){
      if(token!=='doctor-token')return response(403,{message:'PERMISSION_DENIED'});
      const b=this.body(options),index=this.appointments.findIndex(a=>a.id===b.p_id);
      if(index<0)return response(404,{message:'APPOINTMENT_NOT_FOUND'});
      this.appointments[index]={...this.appointments[index],...b.p_data,appointment_time:b.p_data.appointment_time?`${b.p_data.appointment_time}:00`:null,updated_at:'2026-10-27T11:00:00Z'};
      return response(200,{...this.appointments[index],_confirmed:true});
    }
    if(endpoint.endsWith('/oravena_save_record')){
      if(token!=='doctor-token')return response(403,{message:'PERMISSION_DENIED'});
      const b=this.body(options),existing=this.records.find(r=>r.record_type===b.p_record_type&&r.patient_id===b.p_patient_id);
      const row={id:existing?.id||`record-${++this.counter}`,record_type:b.p_record_type,patient_id:b.p_patient_id,payload:b.p_payload,patient_visible:b.p_record_type==='tooth'?true:b.p_patient_visible,created_at:'2026-10-27T10:00:00Z',updated_at:'2026-10-27T11:00:00Z',_confirmed:true};
      if(existing)Object.assign(existing,row);else this.records.unshift(row);
      return response(200,row);
    }
    return response(404,{message:`Unhandled ${endpoint}`});
  }
}

(async()=>{
  const server=new MockServer();
  const patient=device('patient-token','patient',server);
  const doctor=device('doctor-token','doctor',server);

  const appointmentId=await patient.bookAppointment({name:'مريض الاختبار',email:'patient@test.local',phone:'0100000000',age:30,service:'كشف'});
  assert.equal(appointmentId,'appointment-1','patient booking must return the persisted id');

  let doctorCore=await doctor.loadCore();
  assert.equal(doctorCore.appointments.length,1,'doctor must read patient booking from shared data');

  const saved=await doctor.saveAppointment({patientId:'patient-1',service:'كشف',date:'2026-11-02',time:'14:30',doctor:'د. اختبار',status:'مؤكد'},appointmentId,doctorCore.patients[0]);
  assert.equal(saved.status,'confirmed');
  assert.equal(String(saved.appointment_time).slice(0,5),'14:30');

  const secondPatientDevice=device('patient-token','patient',server);
  let patientCore=await secondPatientDevice.loadCore();
  assert.equal(patientCore.appointments[0].status,'مؤكد','patient must see doctor status on another device');
  assert.equal(patientCore.appointments[0].date,'2026-11-02');
  assert.equal(patientCore.appointments[0].time,'14:30');

  const teeth={1:{status:'filling',stage:'الحشو النهائي',needs:'متابعة',note:'ثابت'}};
  await doctor.saveClinicRecord('teeth',{patientId:'patient-1',teeth,patientVisible:true});
  patientCore=await secondPatientDevice.loadCore();
  assert.deepEqual(JSON.parse(JSON.stringify(patientCore.teeth['patient-1'])),teeth,'patient must read latest persisted odontogram');

  await assert.rejects(
    ()=>secondPatientDevice.saveAppointment({patientId:'patient-1',service:'كشف',status:'ملغي'},appointmentId,patientCore.patients[0]),
    /PERMISSION_DENIED/,
    'patient cannot execute doctor appointment updates'
  );

  const afterRefresh=await secondPatientDevice.loadCore();
  assert.equal(afterRefresh.appointments[0].status,'مؤكد','refresh must not lose persisted appointment data');
  assert.equal(afterRefresh.teeth['patient-1'][1].status,'filling','refresh must not lose tooth state');

  const sql=fs.readFileSync(path.join(root,'supabase','ORAVENA-DATA-SYNC-REPAIR-V22.sql'),'utf8');
  assert.match(sql,/begin;[\s\S]*commit;/i,'migration must be transactional');
  assert.match(sql,/r\.payload-'internal'/,'patient payload must remove internal session notes server-side');
  assert.match(sql,/patients_one_file_per_auth_user/,'one patient file per auth account is enforced');
  assert.match(sql,/clinic_records_one_tooth_map_per_patient/,'one active odontogram per patient is enforced');
  assert.match(sql,/revoke insert,update,delete/i,'direct client writes must be blocked');
  assert.doesNotMatch(sql,/delete\s+from\s+public\.(patients|appointments|clinic_records)/i,'migration must not delete operational data');

  console.log('PASS: booking, shared reads, appointment sync, odontogram sync, refresh persistence, permissions, SQL safeguards');
})().catch(error=>{console.error(error);process.exitCode=1});
