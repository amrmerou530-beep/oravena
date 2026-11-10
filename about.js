const languages=['ar','tr','en'];
const copy={
  ar:{
    navHome:'الرئيسية',navStory:'قصتنا',navAccount:'حسابي',bookNow:'احجز موعدًا',backHome:'العودة للرئيسية',footerText:'رعاية أسنان حديثة بتجربة واضحة وآمنة.',navServices:'الخدمات',navJourney:'رحلة العلاج',
    scene1Kicker:'هنا تبدأ الحكاية',scene1Title:'رعاية ترى الإنسان<br>قبل أن ترى السن',scene1Text:'في ORAVENA يبدأ العلاج بفهمك: قلقك، وقتك، وما تحتاج إلى معرفته قبل أي خطوة.',scrollHint:'مرّر لاكتشاف القصة',
    scene2Kicker:'رؤيتنا',scene2Title:'طب أكثر وضوحًا.<br>تجربة أكثر إنسانية.',scene2Text:'نريد لكل مريض أن يرى الطريق كاملًا: تشخيص مفهوم، بدائل واضحة، وخطة يعرف أين تبدأ وإلى أين تصل.',visionPoint1:'وضوح قبل القرار',visionPoint2:'خطة مترابطة',visionPoint3:'متابعة لا تنقطع',
    scene3Kicker:'خبرتنا',scene3Title:'الدقة ليست لحظة.<br>إنها طريقة عمل.',scene3Text:'نقرأ التفاصيل، نشرح ما نراه، ونبني كل قرار على صورة كاملة لحالتك؛ لأن الخبرة الحقيقية تظهر في الخطوات الصغيرة.',expertisePoint1:'تشخيص مدروس',expertisePoint2:'قرار مشترك',expertisePoint3:'تنفيذ دقيق',
    scene4Kicker:'التكنولوجيا',scene4Title:'تقنية تكشف التفاصيل.<br>ولا تخفي الإنسان.',scene4Text:'المسح الرقمي، التصوير الدقيق، وخريطة الأسنان التفاعلية أدوات تجعل المعلومة أوضح والعلاج أكثر قابلية للتوقع.',techPoint1:'تصوير رقمي',techPoint2:'خريطة تفاعلية',techPoint3:'سجل مترابط',
    scene5Kicker:'تجربة المريض',scene5Title:'الراحة تبدأ<br>حين تعرف ما يحدث.',scene5Text:'نستمع أولًا، نشرح بهدوء، ونبقي مواعيدك وخطتك وحسابك في رحلة واحدة؛ لتبقى مطمئنًا داخل العيادة وبعدها.',patientQuote:'«الثقة ليست وعدًا نقوله؛ بل تجربة يشعر بها المريض في كل زيارة.»',
    scene6Kicker:'وعدنا',scene6Title:'دقة طبية.<br>وضوح إنساني.',scene6Text:'أن نحترم وقتك وخصوصيتك وحقك في الفهم، وأن تظل كل خطوة في علاجك واضحة ومحفوظة.',
    progress1:'البداية',progress2:'رؤيتنا',progress3:'خبرتنا',progress4:'التكنولوجيا',progress5:'تجربة المريض',progress6:'وعدنا'
  },
  tr:{
    navHome:'Ana Sayfa',navStory:'Hikayemiz',navAccount:'Hesabım',bookNow:'Randevu Al',backHome:'Ana sayfaya dön',footerText:'Açık ve güvenli bir deneyimle modern diş bakımı.',navServices:'Hizmetler',navJourney:'Tedavi Yolculuğu',
    scene1Kicker:'Hikâye burada başlıyor',scene1Title:'Dişten önce<br>insanı gören bakım',scene1Text:'ORAVENA’da tedavi sizi anlamakla başlar: kaygınız, zamanınız ve her adımdan önce bilmeniz gerekenler.',scrollHint:'Hikâyeyi keşfetmek için kaydırın',
    scene2Kicker:'Vizyonumuz',scene2Title:'Daha açık tıp.<br>Daha insani deneyim.',scene2Text:'Her hastanın yolu bütünüyle görmesini istiyoruz: anlaşılır teşhis, açık seçenekler ve başlangıcı ile hedefi belli bir plan.',visionPoint1:'Karardan önce açıklık',visionPoint2:'Bağlantılı plan',visionPoint3:'Kesintisiz takip',
    scene3Kicker:'Deneyimimiz',scene3Title:'Hassasiyet bir an değil.<br>Bir çalışma biçimidir.',scene3Text:'Ayrıntıları okur, gördüklerimizi açıklar ve her kararı durumunuzun bütününe göre veririz; gerçek deneyim küçük adımlarda görünür.',expertisePoint1:'Düşünülmüş teşhis',expertisePoint2:'Ortak karar',expertisePoint3:'Hassas uygulama',
    scene4Kicker:'Teknoloji',scene4Title:'Ayrıntıyı gösteren teknoloji.<br>İnsanı gölgelemeyen bakım.',scene4Text:'Dijital tarama, hassas görüntüleme ve etkileşimli diş haritası; bilgiyi daha açık, tedaviyi daha öngörülebilir kılar.',techPoint1:'Dijital görüntüleme',techPoint2:'Etkileşimli harita',techPoint3:'Bağlantılı kayıt',
    scene5Kicker:'Hasta deneyimi',scene5Title:'Rahatlık, ne olduğunu<br>bildiğinizde başlar.',scene5Text:'Önce dinler, sakin biçimde açıklar; randevunuzu, planınızı ve hesabınızı tek yolculukta tutarız.',patientQuote:'“Güven söylediğimiz bir vaat değil, hastanın her ziyarette hissettiği deneyimdir.”',
    scene6Kicker:'Sözümüz',scene6Title:'Tıbbi hassasiyet.<br>İnsani açıklık.',scene6Text:'Zamanınıza, gizliliğinize ve anlama hakkınıza saygı duymak; tedavinizin her adımını açık ve kayıtlı tutmak.',
    progress1:'Başlangıç',progress2:'Vizyonumuz',progress3:'Deneyimimiz',progress4:'Teknoloji',progress5:'Hasta deneyimi',progress6:'Sözümüz'
  },
  en:{
    navHome:'Home',navStory:'Our story',navAccount:'My account',bookNow:'Book an appointment',backHome:'Back to home',footerText:'Modern dental care with a clear, secure experience.',navServices:'Services',navJourney:'Care Journey',
    scene1Kicker:'The story begins here',scene1Title:'Care that sees the person<br>before the tooth',scene1Text:'At ORAVENA, treatment begins by understanding you: your concerns, your time and what you need to know before every step.',scrollHint:'Scroll to discover the story',
    scene2Kicker:'Our vision',scene2Title:'Clearer medicine.<br>A more human experience.',scene2Text:'We want every patient to see the full path: an understandable diagnosis, clear options and a plan with a visible beginning and destination.',visionPoint1:'Clarity before decisions',visionPoint2:'Connected plan',visionPoint3:'Continuous follow-up',
    scene3Kicker:'Our expertise',scene3Title:'Precision is not a moment.<br>It is how we work.',scene3Text:'We read the details, explain what we see and build every decision on the complete picture, because real expertise lives in the small steps.',expertisePoint1:'Considered diagnosis',expertisePoint2:'Shared decision',expertisePoint3:'Precise execution',
    scene4Kicker:'Technology',scene4Title:'Technology that reveals detail.<br>Without hiding the human.',scene4Text:'Digital scanning, precise imaging and an interactive dental map make information clearer and treatment more predictable.',techPoint1:'Digital imaging',techPoint2:'Interactive map',techPoint3:'Connected record',
    scene5Kicker:'Patient experience',scene5Title:'Comfort begins<br>when you know what is happening.',scene5Text:'We listen first, explain calmly and keep your appointments, plan and account in one journey, so you feel reassured in the clinic and beyond.',patientQuote:'“Trust is not a promise we say. It is an experience patients feel at every visit.”',
    scene6Kicker:'Our promise',scene6Title:'Medical precision.<br>Human clarity.',scene6Text:'To respect your time, privacy and right to understand, keeping every step of your care clear and safely recorded.',
    progress1:'Beginning',progress2:'Our vision',progress3:'Our expertise',progress4:'Technology',progress5:'Patient experience',progress6:'Our promise'
  }
};

const root=document.documentElement,languageButton=document.getElementById('languageButton');
let currentLanguage=localStorage.getItem('oravenaLanguage')||'ar';
function updateAccountNavigation(){
  const access=window.OravenaDB?.access();
  document.querySelectorAll('.account-link').forEach(link=>link.href=access?'system.html':'login.html');
  const labels={ar:{admin:'المدير الرئيسي',doctor:'الدكتور',employee:'الموظف'},tr:{admin:'Ana Yönetici',doctor:'Doktor',employee:'Çalışan'},en:{admin:'Main Admin',doctor:'Doctor',employee:'Employee'}};
  document.querySelectorAll('.role-access').forEach(link=>{const visible=access&&['admin','doctor','employee'].includes(access.account_type);link.hidden=!visible;if(visible){link.textContent=labels[currentLanguage][access.account_type];link.href='system.html'}});
}
function setLanguage(language){
  currentLanguage=languages.includes(language)?language:'ar';localStorage.setItem('oravenaLanguage',currentLanguage);root.lang=currentLanguage;root.dir=currentLanguage==='ar'?'rtl':'ltr';languageButton.textContent=currentLanguage.toUpperCase();
  document.querySelectorAll('[data-i18n]').forEach(element=>{const value=copy[currentLanguage][element.dataset.i18n];if(value!==undefined)element.innerHTML=value});
  updateAccountNavigation();
}
languageButton.addEventListener('click',()=>setLanguage(languages[(languages.indexOf(currentLanguage)+1)%languages.length]));setLanguage(currentLanguage);

const menuButton=document.getElementById('menuButton'),mobileNav=document.getElementById('mobileNav');
menuButton.addEventListener('click',()=>{const open=mobileNav.hidden;mobileNav.hidden=!open;menuButton.setAttribute('aria-expanded',String(open))});
mobileNav.querySelectorAll('a').forEach(link=>link.addEventListener('click',()=>{mobileNav.hidden=true;menuButton.setAttribute('aria-expanded','false')}));

const story=document.querySelector('[data-story-scroll]'),stage=document.querySelector('[data-story-stage]'),scenes=[...document.querySelectorAll('[data-story-scene]')],progressButtons=[...document.querySelectorAll('[data-story-go]')],progressLine=document.querySelector('[data-story-progress-line]'),counter=document.querySelector('[data-story-counter]'),topbar=document.querySelector('.story-topbar');
const clamp=(value,min=0,max=1)=>Math.min(max,Math.max(min,value));
const reducedMotion=matchMedia('(prefers-reduced-motion: reduce)').matches;
let storyProgress=0,activeScene=0,renderQueued=false,pointerX=0,pointerY=0;

function storyMetrics(){const start=story.offsetTop,end=Math.max(1,story.offsetHeight-innerHeight);return{start,end}}
function setActiveScene(index){
  if(index===activeScene&&scenes[index]?.classList.contains('is-active'))return;
  activeScene=index;
  scenes.forEach((scene,sceneIndex)=>{const active=sceneIndex===index;scene.classList.toggle('is-active',active);scene.setAttribute('aria-hidden',String(!active))});
  progressButtons.forEach((button,buttonIndex)=>{const active=buttonIndex===index;button.classList.toggle('is-active',active);if(active)button.setAttribute('aria-current','step');else button.removeAttribute('aria-current')});
  counter.textContent=String(index+1).padStart(2,'0');
}
function renderStory(){
  renderQueued=false;if(reducedMotion)return;
  const {start,end}=storyMetrics();storyProgress=clamp((scrollY-start)/end);const position=storyProgress*(scenes.length-1);setActiveScene(Math.round(position));
  progressLine.style.transform=`scaleY(${storyProgress})`;
  stage.style.setProperty('--orv-pointer-x',pointerX.toFixed(3));stage.style.setProperty('--orv-pointer-y',pointerY.toFixed(3));
  scenes.forEach((scene,index)=>{const delta=position-index,distance=Math.abs(delta),visibility=clamp(1-distance*1.2),future=delta<0;scene.style.setProperty('--orv-scene-opacity',visibility.toFixed(3));scene.style.setProperty('--orv-scene-y',`${(future?1:-1)*Math.min(distance,1)*8}vh`);scene.style.setProperty('--orv-scene-scale',(1+Math.min(distance,1)*.075).toFixed(3));scene.style.setProperty('--orv-scene-blur',`${Math.min(distance*10,10).toFixed(2)}px`);scene.style.setProperty('--orv-scene-reveal',`${clamp(100-(future?distance*100:0),0,100)}%`);scene.style.setProperty('--orv-content-x',`${(future?1:-1)*Math.min(distance,1)*34}px`)});
  topbar.classList.toggle('scrolled',scrollY>36);
}
function requestStoryRender(){if(!renderQueued){renderQueued=true;requestAnimationFrame(renderStory)}}
addEventListener('scroll',requestStoryRender,{passive:true});addEventListener('resize',requestStoryRender,{passive:true});
addEventListener('pointermove',event=>{pointerX=(event.clientX/innerWidth-.5)*2;pointerY=(event.clientY/innerHeight-.5)*2;requestStoryRender()},{passive:true});
progressButtons.forEach(button=>button.addEventListener('click',()=>{const {start,end}=storyMetrics(),index=Number(button.dataset.storyGo);scrollTo({top:start+(index/(scenes.length-1))*end,behavior:reducedMotion?'auto':'smooth'})}));

function createParticleField(){
  const canvas=document.querySelector('[data-story-particles]'),context=canvas?.getContext('2d');if(!canvas||!context||reducedMotion)return;
  const particles=Array.from({length:44},(_,index)=>({x:(index*73%101)/100,y:(index*47%97)/100,r:.5+(index%4)*.35,s:.00008+(index%5)*.000025,a:.12+(index%5)*.035}));let width=0,height=0,last=0;
  function resize(){const ratio=Math.min(devicePixelRatio||1,2);width=innerWidth;height=innerHeight;canvas.width=width*ratio;canvas.height=height*ratio;canvas.style.width=`${width}px`;canvas.style.height=`${height}px`;context.setTransform(ratio,0,0,ratio,0,0)}
  function frame(time){const dt=Math.min(32,time-last||16);last=time;context.clearRect(0,0,width,height);for(const particle of particles){particle.y-=particle.s*dt;if(particle.y<-.02)particle.y=1.02;const x=particle.x*width+pointerX*12*particle.r,y=particle.y*height+pointerY*8*particle.r;context.beginPath();context.fillStyle=`rgba(113,230,221,${particle.a})`;context.arc(x,y,particle.r,0,Math.PI*2);context.fill()}requestAnimationFrame(frame)}
  resize();addEventListener('resize',resize,{passive:true});requestAnimationFrame(frame);
}
createParticleField();requestStoryRender();
