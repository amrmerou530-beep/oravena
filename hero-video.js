// تحميل كسول: لا يبدأ تحميل الفيديو إلا بعد تحميل الصفحة وظهور الهيدر
(function(){
  var v=document.querySelector('.ov-hero-video'); if(!v) return;
  var c=navigator.connection||{}; var save=c.saveData||/2g/.test(c.effectiveType||'');
  if(save||matchMedia('(prefers-reduced-motion: reduce)').matches) return; // يبقى الـ poster فقط
  var mobile=matchMedia('(max-width:768px)').matches;
  function start(){
    v.src=mobile?v.dataset.srcMobile:v.dataset.srcDesktop;
    v.play().catch(function(){});
  }
  new IntersectionObserver(function(e,o){
    if(e[0].isIntersecting){ (window.requestIdleCallback||setTimeout)(start); o.disconnect(); }
  }).observe(v);
  document.addEventListener('visibilitychange',function(){document.hidden?v.pause():v.play().catch(function(){});});
})();
