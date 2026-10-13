const languages=['ar','tr','en'];
const copy={
  ar:{backHome:'العودة للرئيسية',visualTitle:'ملفك الطبي،<br><em>واضح وآمن</em>',visualText:'ادخل إلى المواعيد وخطة العلاج والجلسات والملفات المسموح بمشاركتها معك.',welcome:'أهلًا بعودتك',intro:'صفحة دخول واحدة للمريض والطبيب والموظف والإدارة. تظهر صلاحيات الحساب تلقائيًا بعد الدخول.',signInTab:'تسجيل الدخول',signUpTab:'إنشاء حساب',identity:'البريد الإلكتروني أو رقم الهاتف',password:'كلمة المرور',signIn:'دخول آمن',fullName:'الاسم الكامل',email:'البريد الإلكتروني',phone:'رقم الهاتف',newPassword:'كلمة مرور جديدة',createAccount:'إنشاء الحساب',or:'أو',google:'المتابعة باستخدام Google',roleNote:'حسابات فريق العيادة تعمل فقط بالبريد الذي أضافه المدير مسبقًا.'},
  tr:{backHome:'Ana sayfaya dön',visualTitle:'Sağlık kaydınız,<br><em>açık ve güvende</em>',visualText:'Randevularınıza, tedavi planınıza, seanslarınıza ve sizinle paylaşılan dosyalara erişin.',welcome:'Tekrar hoş geldiniz',intro:'Hasta, doktor, çalışan ve yönetim için tek giriş sayfası. Hesap yetkileri otomatik olarak açılır.',signInTab:'Giriş yap',signUpTab:'Hesap oluştur',identity:'E-posta veya telefon numarası',password:'Şifre',signIn:'Güvenli giriş',fullName:'Ad Soyad',email:'E-posta adresi',phone:'Telefon numarası',newPassword:'Yeni şifre',createAccount:'Hesap oluştur',or:'veya',google:'Google ile devam et',roleNote:'Klinik ekip hesapları yalnızca yöneticinin önceden eklediği e-posta ile çalışır.'},
  en:{backHome:'Back to home',visualTitle:'Your medical record,<br><em>clear and secure</em>',visualText:'Access your appointments, treatment plan, sessions and files shared with you.',welcome:'Welcome back',intro:'One sign-in page for patients, doctors, employees and management. Account permissions open automatically.',signInTab:'Sign in',signUpTab:'Create account',identity:'Email or phone number',password:'Password',signIn:'Secure sign in',fullName:'Full name',email:'Email address',phone:'Phone number',newPassword:'New password',createAccount:'Create account',or:'or',google:'Continue with Google',roleNote:'Clinic team accounts work only with an email previously added by the administrator.'}
};
const root=document.documentElement,languageButton=document.getElementById('languageButton'),status=document.getElementById('authStatus');
let current=localStorage.getItem('oravenaLanguage')||'ar';
function setLanguage(lang){current=lang;localStorage.setItem('oravenaLanguage',lang);root.lang=lang;root.dir=lang==='ar'?'rtl':'ltr';languageButton.textContent=lang.toUpperCase();document.querySelectorAll('[data-i18n]').forEach(el=>{const value=copy[lang][el.dataset.i18n];if(value!==undefined)el.innerHTML=value})}
languageButton.addEventListener('click',()=>setLanguage(languages[(languages.indexOf(current)+1)%languages.length]));setLanguage(current);

document.querySelectorAll('[data-view]').forEach(button=>button.addEventListener('click',()=>{
  document.querySelectorAll('[data-view]').forEach(item=>{const active=item===button;item.classList.toggle('active',active);item.setAttribute('aria-selected',String(active))});
  document.querySelectorAll('[data-auth-view]').forEach(view=>view.hidden=view.dataset.authView!==button.dataset.view);
  status.textContent='';status.classList.remove('error');
}));

document.getElementById('signInForm').addEventListener('submit',async event=>{
  event.preventDefault();const form=event.currentTarget,data=new FormData(form),button=form.querySelector('[type=submit]');
  status.textContent=current==='ar'?'جارٍ تسجيل الدخول…':current==='tr'?'Giriş yapılıyor…':'Signing in…';status.classList.remove('error');button.disabled=true;
  try{await window.OravenaDB.signIn(data.get('identity'),data.get('password'));location.replace('system.html')}
  catch{await window.OravenaDB.signOut().catch(()=>{});status.classList.add('error');status.textContent=current==='ar'?'بيانات الدخول غير صحيحة أو الحساب موقوف.':current==='tr'?'Bilgiler yanlış veya hesap askıya alınmış.':'Incorrect details or the account is suspended.';button.disabled=false}
});

document.getElementById('signUpForm').addEventListener('submit',async event=>{
  event.preventDefault();const form=event.currentTarget,data=new FormData(form),button=form.querySelector('[type=submit]');
  status.textContent=current==='ar'?'جارٍ إنشاء الحساب…':current==='tr'?'Hesap oluşturuluyor…':'Creating your account…';status.classList.remove('error');button.disabled=true;
  try{const result=await window.OravenaDB.signUpAccount(data.get('email'),data.get('password'),data.get('fullName'),data.get('phone'));if(result.access){location.replace('system.html');return}status.textContent=current==='ar'?'تم إنشاء الحساب. افتح رسالة التأكيد في بريدك ثم سجّل الدخول.':current==='tr'?'Hesap oluşturuldu. E-postanızdaki onay bağlantısını açın.':'Account created. Open the confirmation link in your email.';form.reset()}
  catch{status.classList.add('error');status.textContent=current==='ar'?'تعذر إنشاء الحساب. قد يكون البريد مستخدمًا بالفعل.':current==='tr'?'Hesap oluşturulamadı. E-posta zaten kullanılıyor olabilir.':'Could not create the account. The email may already be in use.'}
  finally{button.disabled=false}
});

document.getElementById('googleLogin').addEventListener('click',event=>{event.currentTarget.disabled=true;status.textContent=current==='ar'?'جارٍ فتح Google…':current==='tr'?'Google açılıyor…':'Opening Google…';try{window.OravenaDB.signInWithGoogle()}catch{event.currentTarget.disabled=false;status.classList.add('error');status.textContent=current==='ar'?'تعذر بدء تسجيل الدخول بجوجل.':'Could not start Google sign-in.'}});

const oauthReturn=location.hash.includes('access_token=')||new URLSearchParams(location.search).get('oauth')==='google';
if(oauthReturn){status.textContent=current==='ar'?'جارٍ إكمال تسجيل الدخول بجوجل…':current==='tr'?'Google girişi tamamlanıyor…':'Completing Google sign-in…';window.OravenaDB.completeOAuth().then(access=>{if(access)location.replace('system.html')}).catch(async()=>{await window.OravenaDB.signOut().catch(()=>{});status.classList.add('error');status.textContent=current==='ar'?'تعذر تسجيل الدخول بجوجل أو الحساب موقوف.':current==='tr'?'Google girişi başarısız veya hesap askıya alınmış.':'Google sign-in failed or the account is suspended.'})}
else if(window.OravenaDB.session()&&window.OravenaDB.access()){location.replace('system.html')}
