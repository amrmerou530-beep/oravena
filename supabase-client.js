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
    const response=await fetch(config().url.replace(/\/$/,'')+path,{...options,headers:{...headers(options.authenticated!==false),...(options.headers||{})}});
    if(response.status===401&&options.authenticated!==false&&!retried&&session()?.refresh_token){
      await refreshSession();
      return request(path,options,true);
    }
    const body=response.status===204?null:await response.json().catch(()=>null);
    if(!response.ok)throw new Error(body?.msg||body?.message||body?.error_description||'REQUEST_FAILED');
    return body;
  }
  async function signIn(identity,password){
    const field=String(identity).includes('@')?'email':'phone';
    const data=await request('/auth/v1/token?grant_type=password',{method:'POST',authenticated:false,body:JSON.stringify({[field]:String(identity).trim(),password})});
    localStorage.setItem(SESSION_KEY,JSON.stringify(data));
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
    const payload={p_full_name:data.name,p_email:data.email,p_phone:data.phone,p_national_id:data.nationalId||null,p_age:Number(data.age),p_service:data.service};
    try{return await request('/rest/v1/rpc/create_appointment_request',{method:'POST',body:JSON.stringify(payload)})}
    catch(error){
      if(!/function|schema cache|p_email/i.test(error.message))throw error;
      delete payload.p_email;
      return request('/rest/v1/rpc/create_appointment_request',{method:'POST',body:JSON.stringify(payload)});
    }
  }
  async function loadCore(){
    const account=read(ACCESS_KEY);
    const [patients,appointments,records,staff]=await Promise.all([
      request('/rest/v1/patients?select=*&order=created_at.desc'),
      request('/rest/v1/appointments?select=*,patients(full_name,file_number)&order=created_at.desc'),
      request('/rest/v1/clinic_records?select=*&order=created_at.desc'),
      account?.account_type==='admin'?request('/rest/v1/staff_invitations?select=*&order=created_at.desc'):Promise.resolve([])
    ]);
    const recordMap={session:'sessions',treatment_plan:'plans',prescription:'prescriptions',imaging:'imaging',finance:'finance',inventory:'inventory',lab:'labs',message:'messages',notification:'notifications',audit:'audit'};
    const mapped={sessions:[],plans:[],prescriptions:[],imaging:[],finance:[],inventory:[],labs:[],messages:[],notifications:[],audit:[]};
    records.forEach(record=>{
      const key=recordMap[record.record_type];
      if(!key)return;
      const row={id:record.id,...(record.payload||{}),patientId:record.patient_id||'',patientVisible:record.patient_visible,createdAt:record.created_at};
      mapped[key].push(row);
    });
    return {
      patients:patients.map(p=>({id:p.id,file:p.file_number,name:p.full_name,email:p.email||'',phone:p.phone,nationalId:p.national_id||'',age:p.age??'',birth:p.birth_date||'',blood:p.blood_type||'',allergy:p.allergy||'',chronic:p.chronic_conditions||'',meds:p.current_medications||'',doctorNotes:p.doctor_notes||'',contact:p.emergency_contact||'',balance:String(p.balance??0)})),
      appointments:appointments.map(a=>({id:a.id,patientId:a.patient_id,patient:a.patients?.full_name||a.full_name,email:a.email||'',phone:a.phone,service:a.service,date:a.appointment_date||'',time:a.appointment_time||'',doctor:'غير محدد',status:({new_request:'طلب جديد',confirmed:'مؤكد',changed:'معدل',cancelled:'ملغي',completed:'مكتمل'})[a.status]||a.status,changeReason:a.change_reason||'',createdAt:a.created_at})),
      ...mapped,
      staff:staff.map(s=>({id:s.id,name:s.full_name,email:s.email,systemRole:s.account_type,role:s.job_title||'',phone:s.phone||'',shift:'',status:({pending:'بانتظار التفعيل',activated:'نشط',suspended:'موقوف'})[s.status]||s.status,permissions:(s.sections||[]).join(','),permissionTemplates:(s.permission_templates||[]).join(',')}))
    };
  }
  const recordTypes={sessions:'session',plans:'treatment_plan',prescriptions:'prescription',imaging:'imaging',finance:'finance',inventory:'inventory',labs:'lab',messages:'message',notifications:'notification',audit:'audit'};
  async function saveClinicRecord(kind,data,id=''){
    const recordType=recordTypes[kind];
    if(!recordType)throw new Error('UNSUPPORTED_RECORD_TYPE');
    const payload={...data};
    delete payload.id;delete payload.patientId;delete payload.patientVisible;delete payload.createdAt;
    const financeVisible=recordType==='finance'&&['فاتورة علاج','دفعة','استرداد'].includes(data.type);
    const patientVisible=(['session','treatment_plan','prescription','imaging','message'].includes(recordType)||financeVisible)&&data.patientVisible!==false;
    const body={record_type:recordType,patient_id:data.patientId||null,payload,patient_visible:patientVisible};
    if(id){
      const rows=await request(`/rest/v1/clinic_records?id=eq.${encodeURIComponent(id)}&select=*`,{method:'PATCH',headers:{Prefer:'return=representation'},body:JSON.stringify(body)});
      return rows?.[0];
    }
    const rows=await request('/rest/v1/clinic_records?select=*',{method:'POST',headers:{Prefer:'return=representation'},body:JSON.stringify(body)});
    return rows?.[0];
  }
  async function deleteClinicRecord(kind,id){
    if(!recordTypes[kind])throw new Error('UNSUPPORTED_RECORD_TYPE');
    return request(`/rest/v1/clinic_records?id=eq.${encodeURIComponent(id)}`,{method:'DELETE',headers:{Prefer:'return=minimal'}});
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
    try{
      return await request('/rest/v1/rpc/reset_oravena_operational_data',{method:'POST',body:JSON.stringify({p_confirmation:confirmation})});
    }catch(error){
      if(!/schema cache|could not find the function|pgrst202/i.test(error.message||''))throw error;
      await deleteRowsById('clinic_records','record_type=neq.setting');
      await deleteRowsById('appointments');
      await deleteRowsById('patients');
      return {ok:true,mode:'admin_direct'};
    }
  }
  async function saveStaffInvitation(data){
    return request('/rest/v1/rpc/upsert_staff_invitation',{method:'POST',body:JSON.stringify({
      p_email:String(data.email||'').trim().toLowerCase(),p_full_name:data.name,
      p_account_type:data.systemRole,p_job_title:data.role||'',p_phone:data.phone||'',
      p_sections:String(data.permissions||'').split(',').filter(Boolean),
      p_permission_templates:String(data.permissionTemplates||'').split(',').filter(Boolean)
    })});
  }
  async function signUpAccount(email,password,fullName,phone=''){
    const data=await request('/auth/v1/signup',{method:'POST',authenticated:false,body:JSON.stringify({email:String(email).trim().toLowerCase(),password,data:{full_name:fullName||'',phone:phone||''}})});
    if(data?.access_token){
      localStorage.setItem(SESSION_KEY,JSON.stringify(data));
      const access=await request('/rest/v1/rpc/current_account_access',{method:'POST',body:'{}'});
      if(access?.status==='active')localStorage.setItem(ACCESS_KEY,JSON.stringify(access));
      return {data,access};
    }
    return {data,access:null};
  }
  window.OravenaDB={configured,session,access:()=>read(ACCESS_KEY),request,refreshSession,signIn,signInWithGoogle,completeOAuth,signOut,bookAppointment,loadCore,saveClinicRecord,deleteClinicRecord,resetOperationalData,saveStaffInvitation,signUpAccount,signUpStaff:signUpAccount};
})();
