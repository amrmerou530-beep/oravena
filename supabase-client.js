(function(){
  const SESSION_KEY='oravena_auth_session_v1';
  const ACCESS_KEY='oravena_account_access_v1';
  const config=()=>window.ORAVENA_SUPABASE||{};
  const configured=()=>/^https:\/\/.+\.supabase\.co\/?$/.test(config().url||'')&&String(config().anonKey||'').length>40;
  const read=(key)=>{try{return JSON.parse(localStorage.getItem(key)||'null')}catch{return null}};
  const session=()=>read(SESSION_KEY);
  const headers=(authenticated=true)=>{const h={apikey:config().anonKey,'Content-Type':'application/json'};const token=authenticated&&session()?.access_token;if(token)h.Authorization=`Bearer ${token}`;return h};
  let refreshPromise=null;
  async function refreshSession(){
    const refreshToken=session()?.refresh_token;
    if(!refreshToken)throw new Error('SESSION_EXPIRED');
    if(!refreshPromise)refreshPromise=(async()=>{
      const response=await fetch(config().url.replace(/\/$/,'')+'/auth/v1/token?grant_type=refresh_token',{
        method:'POST',headers:headers(false),body:JSON.stringify({refresh_token:refreshToken})
      });
      const body=await response.json().catch(()=>null);
      if(!response.ok||!body?.access_token)throw new Error(body?.message||'SESSION_EXPIRED');
      localStorage.setItem(SESSION_KEY,JSON.stringify(body));
      return body;
    })().finally(()=>{refreshPromise=null});
    return refreshPromise;
  }
  async function request(path,options={},retried=false){
    if(!configured())throw new Error('SUPABASE_NOT_CONFIGURED');
    const response=await fetch(config().url.replace(/\/$/,'')+path,{...options,cache:'no-store',headers:{...headers(options.authenticated!==false),'Cache-Control':'no-cache',...(options.headers||{})}});
    if(response.status===401&&options.authenticated!==false&&!retried&&session()?.refresh_token){
      await refreshSession();
      return request(path,options,true);
    }
    const body=response.status===204?null:await response.json().catch(()=>null);
    if(!response.ok){const error=new Error(body?.msg||body?.message||body?.error_description||body?.hint||'REQUEST_FAILED');error.status=response.status;error.code=body?.code||'';throw error}
    return body;
  }
  const rpcMissing=error=>/function|schema cache|pgrst202|could not find/i.test(error?.message||'');
  let persistencePromise=null;
  async function ensurePersistence(){
    if(!persistencePromise)persistencePromise=request('/rest/v1/rpc/oravena_persistence_health',{method:'POST',body:'{}'}).then(status=>{
      if(!status?.ok||Number(status.version)<22)throw new Error('PERSISTENCE_V22_REQUIRED');
      return status;
    }).catch(error=>{persistencePromise=null;if(rpcMissing(error))throw new Error('PERSISTENCE_V22_REQUIRED');throw error});
    return persistencePromise;
  }
  async function bootstrapAccount(){
    try{return await request('/rest/v1/rpc/oravena_ensure_patient_account',{method:'POST',body:'{}'})}
    catch(error){if(!rpcMissing(error))throw error;return null}
  }
  async function signIn(identity,password){
    const field=String(identity).includes('@')?'email':'phone';
    const data=await request('/auth/v1/token?grant_type=password',{method:'POST',authenticated:false,body:JSON.stringify({[field]:String(identity).trim(),password})});
    localStorage.setItem(SESSION_KEY,JSON.stringify(data));
    await bootstrapAccount();
    const access=await request('/rest/v1/rpc/current_account_access',{method:'POST',body:'{}'});
    if(!access||access.status!=='active')throw new Error('ACCOUNT_NOT_ACTIVE');
    localStorage.setItem(ACCESS_KEY,JSON.stringify(access));
    return access;
  }
  function signInWithGoogle(){
    if(!configured())throw new Error('SUPABASE_NOT_CONFIGURED');
    const redirectTo=new URL('login.html?oauth=google',location.href).href;
    const authorize=new URL(config().url.replace(/\/$/,'')+'/auth/v1/authorize');
    authorize.searchParams.set('provider','google');
    authorize.searchParams.set('redirect_to',redirectTo);
    location.assign(authorize.href);
  }
  async function completeOAuth(){
    const params=new URLSearchParams(location.hash.replace(/^#/,''));
    const oauthError=params.get('error_description')||params.get('error');
    if(oauthError){
      history.replaceState(null,'',location.pathname);
      throw new Error(oauthError);
    }
    const accessToken=params.get('access_token');
    if(!accessToken)return null;
    const oauthSession={
      access_token:accessToken,
      refresh_token:params.get('refresh_token')||'',
      expires_in:Number(params.get('expires_in')||0),
      expires_at:Math.floor(Date.now()/1000)+Number(params.get('expires_in')||0),
      token_type:params.get('token_type')||'bearer'
    };
    localStorage.setItem(SESSION_KEY,JSON.stringify(oauthSession));
    history.replaceState(null,'',location.pathname);
    await bootstrapAccount();
    const access=await request('/rest/v1/rpc/current_account_access',{method:'POST',body:'{}'});
    if(!access||access.status!=='active'){
      await signOut();
      throw new Error('ACCOUNT_NOT_ACTIVE');
    }
    localStorage.setItem(ACCESS_KEY,JSON.stringify(access));
    return access;
  }
  async function signOut(){
    if(configured()&&session())await request('/auth/v1/logout',{method:'POST'}).catch(()=>{});
    [SESSION_KEY,ACCESS_KEY,'oravenaSessionEmail','oravenaSessionRole','oravenaRole'].forEach(k=>localStorage.removeItem(k));
  }
  async function bookAppointment(data){
    if(session())await ensurePersistence();
    const payload={p_full_name:data.name,p_email:data.email,p_phone:data.phone,p_national_id:data.nationalId||null,p_age:Number(data.age),p_service:data.service};
    const id=await request('/rest/v1/rpc/create_appointment_request',{method:'POST',body:JSON.stringify(payload)});
    if(!id)throw new Error('SAVE_NOT_CONFIRMED');
    return id;
  }
  async function loadServices(){
    const rows=await request('/rest/v1/clinic_services?select=*&active=eq.true&order=sort_order.asc,name_ar.asc',{authenticated:false});
    return (rows||[]).map(s=>({id:s.id,nameAr:s.name_ar,nameTr:s.name_tr||s.name_ar,nameEn:s.name_en||s.name_ar,status:s.active?'متاحة':'متوقفة',sortOrder:String(s.sort_order??0)}));
  }
  async function saveService(data,id=''){
    await ensurePersistence();
    const body={
      name_ar:String(data.nameAr||'').trim(),
      name_tr:String(data.nameTr||'').trim()||null,
      name_en:String(data.nameEn||'').trim()||null,
      active:data.status==='متاحة',
      sort_order:Number(data.sortOrder||0),
      updated_at:new Date().toISOString()
    };
    const saved=await request('/rest/v1/rpc/oravena_save_service',{method:'POST',body:JSON.stringify({p_id:id||null,p_data:body})});
    if(!saved?.id)throw new Error('SAVE_NOT_CONFIRMED');
    return saved;
  }
  async function deleteService(id){
    await ensurePersistence();
    const deleted=await request('/rest/v1/rpc/oravena_delete_entity',{method:'POST',body:JSON.stringify({p_entity:'service',p_id:id})});
    if(deleted!==true)throw new Error('DELETE_NOT_CONFIRMED');
    return true;
  }
  const appointmentStatusToDb={
    'طلب جديد':'new_request','مؤكد':'confirmed','معدل':'changed','ملغي':'cancelled','مكتمل':'completed'
  };
  const sameNullable=(left,right)=>String(left??'')===String(right??'');
  async function savePatient(data,id=''){
    await ensurePersistence();
    const body={
      file_number:String(data.file||'').trim()||undefined,
      full_name:String(data.name||'').trim(),
      email:String(data.email||'').trim().toLowerCase()||null,
      phone:String(data.phone||'').trim(),
      national_id:String(data.nationalId||'').trim()||null,
      age:data.age===''||data.age==null?null:Number(data.age),
      birth_date:data.birth||null,
      blood_type:data.blood||null,
      allergy:data.allergy||null,
      chronic_conditions:data.chronic||null,
      current_medications:data.meds||null,
      doctor_notes:data.doctorNotes||null,
      emergency_contact:data.contact||null,
      balance:Number(data.balance||0),
      updated_at:new Date().toISOString()
    };
    if(!body.file_number)delete body.file_number;
    const saved=await request('/rest/v1/rpc/oravena_save_patient',{method:'POST',body:JSON.stringify({p_id:id||null,p_data:body})});
    if(!saved?.id)throw new Error('SAVE_NOT_CONFIRMED');
    if(saved.full_name!==body.full_name||saved.phone!==body.phone||!sameNullable(saved.email,body.email))throw new Error('SAVE_VERIFICATION_FAILED');
    return saved;
  }
  async function saveMyPatient(data){
    await ensurePersistence();
    const body={
      full_name:String(data.name||'').trim(),
      phone:String(data.phone||'').trim(),
      national_id:String(data.nationalId||'').trim()||null,
      age:data.age===''||data.age==null?null:Number(data.age),
      birth_date:data.birth||null,
      blood_type:data.blood||null,
      allergy:data.allergy||null,
      chronic_conditions:data.chronic||null,
      current_medications:data.meds||null,
      emergency_contact:data.contact||null
    };
    const saved=await request('/rest/v1/rpc/oravena_save_my_patient',{method:'POST',body:JSON.stringify({p_data:body})});
    if(!saved?.id)throw new Error('SAVE_NOT_CONFIRMED');
    if(saved.full_name!==body.full_name||saved.phone!==body.phone||!sameNullable(saved.national_id,body.national_id)||!sameNullable(saved.birth_date,body.birth_date)||!sameNullable(saved.blood_type,body.blood_type))throw new Error('SAVE_VERIFICATION_FAILED');
    return saved;
  }
  async function deletePatient(id){
    await ensurePersistence();
    const deleted=await request('/rest/v1/rpc/oravena_delete_entity',{method:'POST',body:JSON.stringify({p_entity:'patient',p_id:id})});
    if(deleted!==true)throw new Error('DELETE_NOT_CONFIRMED');
    return true;
  }
  async function saveAppointment(data,id='',patient={}){
    await ensurePersistence();
    const body={
      patient_id:data.patientId,
      full_name:patient.name||data.patient||'',
      email:String(data.email||patient.email||'').trim().toLowerCase()||null,
      phone:String(patient.phone||data.phone||'').trim(),
      national_id:patient.nationalId||null,
      age:patient.age===''||patient.age==null?null:Number(patient.age),
      service:data.service,
      appointment_date:data.date||null,
      appointment_time:data.time||null,
      doctor_name:data.doctor||null,
      status:data.status==='غير محدد'?'new_request':appointmentStatusToDb[data.status]||data.status||'new_request',
      change_reason:data.changeReason||null,
      updated_at:new Date().toISOString()
    };
    const saved=await request('/rest/v1/rpc/oravena_save_appointment',{method:'POST',body:JSON.stringify({p_id:id||null,p_data:body})});
    if(!saved?.id)throw new Error('SAVE_NOT_CONFIRMED');
    if(saved.patient_id!==body.patient_id||saved.status!==body.status||!sameNullable(saved.appointment_date,body.appointment_date)||!sameNullable(String(saved.appointment_time||'').slice(0,5),String(body.appointment_time||'').slice(0,5)))throw new Error('SAVE_VERIFICATION_FAILED');
    return saved;
  }
  async function deleteAppointment(id){
    await ensurePersistence();
    const deleted=await request('/rest/v1/rpc/oravena_delete_entity',{method:'POST',body:JSON.stringify({p_entity:'appointment',p_id:id})});
    if(deleted!==true)throw new Error('DELETE_NOT_CONFIRMED');
    return true;
  }
  async function markMyNotificationsRead(){
    await ensurePersistence();
    return request('/rest/v1/rpc/mark_my_notifications_read',{method:'POST',body:'{}'});
  }
  async function logEvent(action,details='',patientId=null){
    await ensurePersistence();
    return request('/rest/v1/rpc/oravena_log_event',{method:'POST',body:JSON.stringify({p_action:String(action||''),p_details:String(details||''),p_patient_id:patientId||null})});
  }
  async function loadCore(){
    const account=read(ACCESS_KEY);
    await ensurePersistence();
    if(account?.account_type==='patient')await bootstrapAccount();
    const core=await request('/rest/v1/rpc/oravena_core_data',{method:'POST',body:'{}'});
    if(!core||typeof core!=='object')throw new Error('LOAD_NOT_CONFIRMED');
    const patients=core.patients||[],appointments=core.appointments||[],records=core.records||[],staff=core.staff||[],services=core.services||[];
    const recordMap={session:'sessions',treatment_plan:'plans',prescription:'prescriptions',imaging:'imaging',finance:'finance',inventory:'inventory',lab:'labs',message:'messages',notification:'notifications',audit:'audit'};
    const mapped={sessions:[],plans:[],prescriptions:[],imaging:[],finance:[],inventory:[],labs:[],messages:[],notifications:[],audit:[]};
    const teeth={},toothRecordIds={};
    let settings={},settingsRecordId='';
    records.forEach(record=>{
      if(record.record_type==='tooth'&&record.patient_id){
        // The API returns newest records first. Keep the first map so an old
        // duplicate can never replace the patient's latest odontogram.
        if(toothRecordIds[record.patient_id])return;
        teeth[record.patient_id]=record.payload?.teeth||record.payload||{};
        toothRecordIds[record.patient_id]=record.id;
        return;
      }
      if(record.record_type==='setting'){
        if(!settingsRecordId){settings={...(record.payload||{})};settingsRecordId=record.id}
        return;
      }
      const key=recordMap[record.record_type];
      if(!key)return;
      const row={id:record.id,...(record.payload||{}),patientId:record.patient_id||'',patientVisible:record.patient_visible,createdAt:record.created_at};
      mapped[key].push(row);
    });
    return {
      patients:patients.map(p=>({id:p.id,authUserId:p.auth_user_id||'',file:p.file_number,name:p.full_name,email:p.email||'',phone:/^ACCOUNT-/.test(p.phone||'')?'':p.phone,nationalId:p.national_id||'',age:p.age??'',birth:p.birth_date||'',blood:p.blood_type||'',allergy:p.allergy||'',chronic:p.chronic_conditions||'',meds:p.current_medications||'',doctorNotes:p.doctor_notes||'',contact:p.emergency_contact||'',balance:String(p.balance??0)})),
      appointments:appointments.map(a=>({id:a.id,patientId:a.patient_id,patient:a.full_name,email:a.email||'',phone:a.phone,service:a.service,date:a.appointment_date||'',time:String(a.appointment_time||'').slice(0,5),doctor:a.doctor_name||'غير محدد',status:({new_request:'طلب جديد',confirmed:'مؤكد',changed:'معدل',cancelled:'ملغي',completed:'مكتمل'})[a.status]||a.status,changeReason:a.change_reason||'',createdAt:a.created_at,updatedAt:a.updated_at})),
      ...mapped,
      teeth,toothRecordIds,settings,settingsRecordId,
      services:services.map(s=>({id:s.id,nameAr:s.name_ar,nameTr:s.name_tr||'',nameEn:s.name_en||'',status:s.active?'متاحة':'متوقفة',sortOrder:String(s.sort_order??0)})),
      staff:staff.map(s=>({id:s.id,name:s.full_name,email:s.email,systemRole:s.account_type,role:s.job_title||'',phone:s.phone||'',shift:'',status:({pending:'بانتظار التفعيل',activated:'نشط',suspended:'موقوف'})[s.status]||s.status,permissions:(s.sections||[]).join(','),permissionTemplates:(s.permission_templates||[]).join(',')})),
      serverMeta:core.meta||{}
    };
  }
  const recordTypes={sessions:'session',plans:'treatment_plan',prescriptions:'prescription',imaging:'imaging',finance:'finance',inventory:'inventory',labs:'lab',messages:'message',notifications:'notification',audit:'audit',teeth:'tooth',settings:'setting'};
  async function saveClinicRecord(kind,data,id=''){
    await ensurePersistence();
    const recordType=recordTypes[kind];
    if(!recordType)throw new Error('UNSUPPORTED_RECORD_TYPE');
    const payload={...data};
    delete payload.id;delete payload.patientId;delete payload.patientVisible;delete payload.createdAt;
    const financeVisible=recordType==='finance'&&['فاتورة علاج','دفعة','استرداد'].includes(data.type);
    const patientVisible=(['session','treatment_plan','prescription','imaging','message','tooth'].includes(recordType)||financeVisible)&&data.patientVisible!==false;
    const body={record_type:recordType,patient_id:data.patientId||null,payload,patient_visible:patientVisible};
    const saved=await request('/rest/v1/rpc/oravena_save_record',{method:'POST',body:JSON.stringify({p_id:id||null,p_record_type:recordType,p_patient_id:body.patient_id,p_payload:body.payload,p_patient_visible:body.patient_visible})});
    if(!saved?.id)throw new Error('SAVE_NOT_CONFIRMED');
    if(saved.record_type!==recordType||!sameNullable(saved.patient_id,body.patient_id))throw new Error('SAVE_VERIFICATION_FAILED');
    return saved;
  }
  async function deleteClinicRecord(kind,id){
    if(!recordTypes[kind])throw new Error('UNSUPPORTED_RECORD_TYPE');
    await ensurePersistence();
    const deleted=await request('/rest/v1/rpc/oravena_delete_entity',{method:'POST',body:JSON.stringify({p_entity:'record',p_id:id})});
    if(deleted!==true)throw new Error('DELETE_NOT_CONFIRMED');
    return true;
  }
  async function deleteRowsById(table,filter=''){
    while(true){
      const rows=await request(`/rest/v1/${table}?select=id&limit=500${filter?'&'+filter:''}`);
      const ids=(rows||[]).map(row=>row.id).filter(Boolean);
      if(!ids.length)return;
      for(let index=0;index<ids.length;index+=50){
        const batch=ids.slice(index,index+50).map(encodeURIComponent).join(',');
        await request(`/rest/v1/${table}?id=in.(${batch})`,{method:'DELETE',headers:{Prefer:'return=minimal'}});
      }
    }
  }
  async function resetOperationalData(confirmation){
    await ensurePersistence();
    const result=await request('/rest/v1/rpc/reset_oravena_operational_data',{method:'POST',body:JSON.stringify({p_confirmation:confirmation})});
    if(!result?.ok)throw new Error('RESET_NOT_CONFIRMED');
    return result;
  }
  async function saveStaffInvitation(data){
    await ensurePersistence();
    const saved=await request('/rest/v1/rpc/upsert_staff_invitation',{method:'POST',body:JSON.stringify({
      p_email:String(data.email||'').trim().toLowerCase(),p_full_name:data.name,
      p_account_type:data.systemRole,p_job_title:data.role||'',p_phone:data.phone||'',
      p_sections:String(data.permissions||'').split(',').filter(Boolean),
      p_permission_templates:String(data.permissionTemplates||'').split(',').filter(Boolean)
    })});
    if(!saved)throw new Error('SAVE_NOT_CONFIRMED');
    return saved;
  }
  async function signUpAccount(email,password,fullName,phone=''){
    const data=await request('/auth/v1/signup',{method:'POST',authenticated:false,body:JSON.stringify({email:String(email).trim().toLowerCase(),password,data:{full_name:fullName||'',phone:phone||''}})});
    if(data?.access_token){
      localStorage.setItem(SESSION_KEY,JSON.stringify(data));
      await bootstrapAccount();
      const access=await request('/rest/v1/rpc/current_account_access',{method:'POST',body:'{}'});
      if(access?.status==='active')localStorage.setItem(ACCESS_KEY,JSON.stringify(access));
      return {data,access};
    }
    return {data,access:null};
  }
  function userMessage(error){
    const message=String(error?.message||'');
    if(/invalid login credentials/i.test(message))return 'البريد أو كلمة المرور غير صحيحة.';
    if(/email not confirmed/i.test(message))return 'افتح رسالة تأكيد البريد الإلكتروني أولًا، ثم حاول مرة أخرى.';
    if(/already registered|user already exists/i.test(message))return 'هذا البريد مسجل بالفعل.';
    if(/PERSISTENCE_V22_REQUIRED/.test(message))return 'قاعدة البيانات تحتاج تشغيل ملف إصلاح V22 مرة واحدة.';
    if(/SAVE_VERIFICATION_FAILED|SAVE_NOT_CONFIRMED|SAVE_NOT_VISIBLE/.test(message))return 'الخادم لم يؤكد حفظ كل التعديلات. لم نعرض رسالة نجاح.';
    if(/PERMISSION_DENIED|42501|permission denied/i.test(message))return 'ليست لديك صلاحية لتنفيذ هذا الإجراء.';
    if(/SERVICE_NOT_AVAILABLE/.test(message))return 'الخدمة المختارة لم تعد متاحة.';
    if(/SESSION_EXPIRED|jwt|token/i.test(message))return 'انتهت جلسة الدخول. سجّل الدخول مرة أخرى.';
    if(/network|fetch/i.test(message))return 'تعذر الاتصال بقاعدة البيانات. تحقق من الإنترنت وحاول مجددًا.';
    return message||'حدث خطأ غير معروف.';
  }
  window.OravenaDB={configured,session,access:()=>read(ACCESS_KEY),request,refreshSession,ensurePersistence,bootstrapAccount,signIn,signInWithGoogle,completeOAuth,signOut,bookAppointment,loadServices,saveService,deleteService,savePatient,saveMyPatient,deletePatient,saveAppointment,deleteAppointment,markMyNotificationsRead,logEvent,loadCore,saveClinicRecord,deleteClinicRecord,resetOperationalData,saveStaffInvitation,signUpAccount,signUpStaff:signUpAccount,userMessage};
})();
