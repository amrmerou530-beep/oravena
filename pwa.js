(()=>{
  if('serviceWorker'in navigator)addEventListener('load',()=>navigator.serviceWorker.register('./service-worker.js').catch(error=>console.warn('PWA registration failed',error)));
  const buttons=()=>document.querySelectorAll('[data-install-app]');
  const standalone=matchMedia('(display-mode: standalone)').matches||navigator.standalone===true;
  let installPrompt=null;
  function showButtons(){if(!standalone)buttons().forEach(button=>button.hidden=false)}
  addEventListener('beforeinstallprompt',event=>{event.preventDefault();installPrompt=event;showButtons()});
  addEventListener('appinstalled',()=>buttons().forEach(button=>button.hidden=true));
  document.addEventListener('click',async event=>{
    const button=event.target.closest('[data-install-app]');if(!button)return;
    if(installPrompt){await installPrompt.prompt();await installPrompt.userChoice;installPrompt=null;button.hidden=true;return}
    const ios=/iphone|ipad|ipod/i.test(navigator.userAgent);
    alert(ios?'لتثبيت ORAVENA: اضغط زر المشاركة ثم اختر «إضافة إلى الشاشة الرئيسية».':'من قائمة المتصفح اختر «تثبيت التطبيق» أو «إضافة إلى الشاشة الرئيسية».');
  });
  if(/iphone|ipad|ipod/i.test(navigator.userAgent)&&!standalone)showButtons();
})();
