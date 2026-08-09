"""GTOL PC Control — interface PWA sobre, mobile-first.

Une seule page, cinq onglets en barre basse (Accueil, Écran, Fichiers, Système,
Terminal). Monochrome, dense, sans fioriture : uniquement des commandes utiles.
Toutes les actions passent par /api/action (liste blanche stricte côté serveur).
"""

STYLE = r"""
*,*::before,*::after{box-sizing:border-box}
:root{
  color-scheme:dark;
  --bg:#0a0a0b;--surface:#141416;--raised:#1b1b1e;--line:#26262b;--edge:#34343a;
  --text:#f3f3f1;--dim:#8c8c93;--faint:#5c5c63;--inverse:#0a0a0b;
  --ok:#5fd39a;--warn:#e6b54a;--bad:#e8705a;
  --r:14px;--ri:10px;--nav:60px;
  font-family:ui-sans-serif,-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,system-ui,sans-serif;
  -webkit-tap-highlight-color:transparent
}
.mono,.val,.crumb,.term,.pill,.kv b{font-family:ui-monospace,"SF Mono",SFMono-Regular,Consolas,"Liberation Mono",monospace;font-variant-numeric:tabular-nums}
html{background:var(--bg)}
body{margin:0;min-height:100dvh;background:var(--bg);color:var(--text);font-size:14px;line-height:1.45;-webkit-font-smoothing:antialiased;-moz-osx-font-smoothing:grayscale}
button,input,textarea,select{font:inherit;color:inherit}
[hidden]{display:none!important}
::selection{background:var(--text);color:var(--inverse)}
button:focus-visible,input:focus-visible,textarea:focus-visible,select:focus-visible,a:focus-visible{outline:2px solid var(--text);outline-offset:2px}
button{cursor:pointer}button:disabled{opacity:.4;cursor:not-allowed}

/* ---- Structure ---- */
.app{width:min(100%,720px);margin-inline:auto;padding:max(14px,env(safe-area-inset-top)) 14px calc(var(--nav) + 22px + env(safe-area-inset-bottom))}
.top{display:flex;align-items:center;justify-content:space-between;gap:12px;height:46px}
.brand{display:flex;align-items:center;gap:9px;min-width:0}
.logo{display:grid;width:30px;height:30px;flex:none;place-items:center;border-radius:8px;background:var(--text);color:var(--inverse);font-size:11px;font-weight:800}
.brand b{font-size:14px;letter-spacing:-.01em}
.brand small{display:block;color:var(--dim);font-size:10px;line-height:1}
.top-right{display:flex;align-items:center;gap:8px}
.stat{display:inline-flex;align-items:center;gap:6px;color:var(--dim);font-size:11px}
.dot{width:8px;height:8px;border-radius:50%;background:var(--faint);flex:none}
.dot.on{background:var(--ok)}.dot.off{background:var(--faint)}.dot.warn{background:var(--warn)}.dot.bad{background:var(--bad)}
.dot.busy{background:var(--warn);animation:blink 1s infinite}
@keyframes blink{50%{opacity:.3}}
.iconbtn{display:grid;width:38px;height:38px;place-items:center;border:1px solid var(--line);border-radius:var(--ri);background:transparent;font-size:16px}
.iconbtn:active{background:var(--raised)}

.view{margin-top:16px;display:grid;gap:14px}
.card{border:1px solid var(--line);border-radius:var(--r);background:var(--surface);overflow:hidden}
.card-h{display:flex;align-items:center;justify-content:space-between;gap:10px;padding:13px 15px;border-bottom:1px solid var(--line)}
.card-h h2{margin:0;font-size:13px;font-weight:600;letter-spacing:-.01em}
.card-h .sub{color:var(--dim);font-size:10px;text-transform:uppercase;letter-spacing:.08em}
.card-b{padding:14px}
.card-b.flush{padding:0}

.msg{display:flex;align-items:center;gap:10px;font-size:13px;color:var(--text)}
.msg .t{color:var(--dim);font-size:11px}

/* ---- Metrics ---- */
.grid{display:grid;grid-template-columns:repeat(3,1fr);gap:1px;background:var(--line)}
.cell{padding:13px 14px;background:var(--surface);min-width:0}
.cell .k{color:var(--dim);font-size:10px;text-transform:uppercase;letter-spacing:.06em}
.cell .val{display:block;margin-top:9px;font-size:17px;font-weight:650;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.cell .bar{height:3px;margin-top:9px;background:var(--line);border-radius:2px;overflow:hidden}
.cell .bar i{display:block;height:100%;width:0;background:var(--text);transition:width .4s}
.cell .bar i.hot{background:var(--bad)}

/* ---- Buttons ---- */
.btn{display:flex;align-items:center;justify-content:center;gap:8px;width:100%;min-height:48px;padding:0 14px;border:1px solid var(--edge);border-radius:var(--ri);background:transparent;color:var(--text);font-size:13px;font-weight:550;letter-spacing:.01em;transition:background .12s,border-color .12s,transform .05s}
.btn:active{transform:scale(.98);background:var(--raised)}
.btn.pri{background:var(--text);color:var(--inverse);border-color:var(--text);font-weight:700}
.btn.pri:active{background:#d9d9d6}
.btn.bad{border-color:var(--edge);color:var(--bad)}
.btn.bad:active{background:var(--bad);color:var(--inverse);border-color:var(--bad)}
.btn.sm{min-height:38px;font-size:12px;padding:0 11px}
.btn.armed{background:var(--warn);color:var(--inverse);border-color:var(--warn)}
.row{display:grid;gap:9px}
.row.two{grid-template-columns:1fr 1fr}
.row.three{grid-template-columns:1fr 1fr 1fr}
.seg{display:grid;grid-template-columns:1fr 1fr;gap:4px;padding:4px;border:1px solid var(--line);border-radius:var(--ri)}
.seg button{min-height:40px;border:0;border-radius:7px;background:transparent;color:var(--dim);font-size:12px;font-weight:600}
.seg button.active{background:var(--text);color:var(--inverse)}

/* ---- Screen tab ---- */
.screen-wrap{position:relative;background:#000;border-radius:0;line-height:0;touch-action:manipulation;user-select:none}
.screen-wrap img{display:block;width:100%;height:auto}
.screen-wrap .ph{display:grid;place-items:center;height:210px;color:var(--faint);font-size:12px}
.screen-hint{position:absolute;inset-inline:0;bottom:0;padding:6px 10px;background:linear-gradient(transparent,rgba(0,0,0,.6));color:#cfcfcf;font-size:10px;text-align:center;pointer-events:none}
.tap{position:absolute;width:26px;height:26px;margin:-13px 0 0 -13px;border:2px solid #fff;border-radius:50%;pointer-events:none;animation:tap .4s ease-out forwards}
@keyframes tap{from{transform:scale(.3);opacity:1}to{transform:scale(1.3);opacity:0}}
.keybar{display:flex;gap:8px}
.keybar input{flex:1;min-height:44px;padding:0 12px;border:1px solid var(--edge);border-radius:var(--ri);background:var(--bg)}
.keys{display:grid;grid-template-columns:repeat(6,1fr);gap:6px}
.keys button{min-height:40px;border:1px solid var(--line);border-radius:8px;background:transparent;color:var(--text);font-size:12px}
.keys button:active{background:var(--raised)}
.vol{display:flex;align-items:center;gap:12px}
.vol input[type=range]{flex:1;accent-color:var(--text);height:28px}
.vol .val{width:44px;text-align:right;font-size:13px}

/* ---- Files ---- */
.crumb{display:flex;align-items:center;gap:4px;flex-wrap:wrap;padding:11px 14px;border-bottom:1px solid var(--line);font-size:12px;color:var(--dim);overflow:hidden}
.crumb b{color:var(--text)}
.list{display:grid}
.item{display:grid;grid-template-columns:26px 1fr auto;align-items:center;gap:11px;padding:12px 14px;border-bottom:1px solid var(--line);background:transparent;border-left:0;border-right:0;border-top:0;text-align:left;width:100%}
.item:last-child{border-bottom:0}
.item:active{background:var(--raised)}
.item .ic{font-size:16px;text-align:center;color:var(--dim)}
.item .nm{min-width:0;overflow:hidden}
.item .nm b{display:block;font-size:13px;font-weight:500;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.item .nm span{color:var(--faint);font-size:10px}
.item .go{color:var(--faint);font-size:13px}
.empty{padding:26px;text-align:center;color:var(--faint);font-size:12px}

/* ---- Terminal ---- */
.term{margin:0;padding:14px;background:#050506;border-radius:var(--ri);max-height:46vh;overflow:auto;font-size:12px;line-height:1.5;white-space:pre-wrap;word-break:break-word;color:#d8d8d8;border:1px solid var(--line)}
.term .cmd{color:var(--text)}.term .err{color:var(--bad)}.term .ok{color:var(--dim)}
.term-in{display:flex;gap:8px;margin-top:10px}
.term-in input{flex:1;min-height:46px;padding:0 12px;border:1px solid var(--edge);border-radius:var(--ri);background:var(--bg)}

/* ---- Processes ---- */
.proc{display:grid;grid-template-columns:1fr auto auto;align-items:center;gap:10px;padding:11px 14px;border-bottom:1px solid var(--line)}
.proc:last-child{border-bottom:0}
.proc .nm{min-width:0}
.proc .nm b{display:block;font-size:12px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.proc .nm span{color:var(--faint);font-size:10px}
.proc .mem{color:var(--dim);font-size:12px;white-space:nowrap}

.kv{display:flex;align-items:center;justify-content:space-between;gap:12px;padding:11px 0;border-bottom:1px solid var(--line)}
.kv:last-child{border-bottom:0}
.kv span{color:var(--dim);font-size:11px;text-transform:uppercase;letter-spacing:.05em}
.kv b{font-size:13px;font-weight:600}
.apps{display:grid;grid-template-columns:repeat(3,1fr);gap:9px}
.apps button{display:grid;place-items:center;gap:6px;min-height:64px;padding:8px;border:1px solid var(--line);border-radius:var(--ri);background:transparent;font-size:11px;font-weight:500}
.apps button:active{background:var(--raised)}
.apps .ap-ic{font-size:19px}

/* ---- Nav ---- */
.nav{position:fixed;inset-inline:0;bottom:0;z-index:40;display:grid;grid-template-columns:repeat(5,1fr);height:calc(var(--nav) + env(safe-area-inset-bottom));padding-bottom:env(safe-area-inset-bottom);background:rgba(12,12,13,.92);backdrop-filter:blur(14px);border-top:1px solid var(--line)}
.nav button{display:grid;place-items:center;gap:3px;border:0;background:transparent;color:var(--faint);font-size:9.5px;letter-spacing:.02em}
.nav button .ni{font-size:19px;line-height:1}
.nav button.active{color:var(--text)}
.nav button:active{background:var(--raised)}

/* ---- Gate ---- */
.gate{display:grid;min-height:100dvh;place-items:center;padding:22px}
.gate .box{width:min(100%,380px)}
.gate .logo{width:44px;height:44px;font-size:15px;margin-bottom:22px}
.gate h1{margin:0 0 6px;font-size:26px;letter-spacing:-.03em}
.gate p{margin:0 0 22px;color:var(--dim);font-size:13px}
.gate input{width:100%;min-height:52px;padding:0 15px;border:1px solid var(--edge);border-radius:var(--ri);background:var(--surface);font-size:16px;margin-bottom:10px}
.gate .err{min-height:18px;margin:8px 2px 0;color:var(--bad);font-size:12px}

/* ---- Toast / busy ---- */
.busy{position:fixed;inset:0 0 auto;z-index:60;height:2px;background:transparent;overflow:hidden}
.busy.on::after{content:"";position:absolute;inset-block:0;width:40%;background:var(--text);animation:load 1s infinite ease-in-out}
@keyframes load{from{left:-40%}to{left:100%}}
.toast{position:fixed;left:50%;bottom:calc(var(--nav) + 20px + env(safe-area-inset-bottom));transform:translateX(-50%);z-index:70;max-width:90%;padding:11px 16px;border:1px solid var(--edge);border-radius:999px;background:var(--raised);color:var(--text);font-size:12px;box-shadow:0 8px 24px rgba(0,0,0,.5);opacity:0;pointer-events:none;transition:opacity .2s,transform .2s}
.toast.show{opacity:1;transform:translateX(-50%) translateY(0)}
.toast.bad{border-color:var(--bad)}

dialog{width:min(100% - 32px,400px);padding:0;border:1px solid var(--edge);border-radius:var(--r);background:var(--surface);color:var(--text)}
dialog::backdrop{background:rgba(0,0,0,.7);backdrop-filter:blur(3px)}
.dlg{padding:22px}
.dlg h3{margin:0 0 8px;font-size:17px}
.dlg p{margin:0 0 18px;color:var(--dim);font-size:13px;word-break:break-word}
.dlg .row{grid-template-columns:1fr 1fr}
.dlg input,.dlg textarea{width:100%;min-height:46px;padding:11px;border:1px solid var(--edge);border-radius:var(--ri);background:var(--bg);font-size:15px;margin-bottom:12px}
.dlg textarea{min-height:150px;resize:vertical;font-family:ui-monospace,Consolas,monospace;font-size:13px}
@media(prefers-reduced-motion:reduce){*{animation-duration:.01ms!important;transition-duration:.01ms!important}}
"""

SCRIPT = r"""
(()=>{"use strict";
const $=(s,r=document)=>r.querySelector(s);
const KEY="pcControlKey";
const gate=$("#gate"),app=$("#app"),field=$("#key"),gateErr=$("#gateErr"),busy=$("#busy"),toastEl=$("#toast");
let key=localStorage.getItem(KEY)||"";
let data=null, tab="home", stream=null, streamStop=null, toastTimer=0;
let screenTimer=0, screenAuto=false, lastMonitor=-1, monitors=[], reqBusy=0;
let filePath="", clickMode="left";
const H={};  // handlers per tab activation

const clamp=(v,a,b)=>Math.max(a,Math.min(b,v));
const fmtDur=m=>{if(!Number.isFinite(m))return"—";const h=Math.floor(m/60),n=Math.round(m%60);return h?`${h}h${String(n).padStart(2,"0")}`:`${n}min`};
const esc=s=>String(s).replace(/[&<>]/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;"}[c]));
function vibe(ms=8){try{navigator.vibrate&&navigator.vibrate(ms)}catch{}}
function setBusy(on){reqBusy=Math.max(0,reqBusy+(on?1:-1));busy.classList.toggle("on",reqBusy>0)}
function toast(text,bad){toastEl.textContent=text;toastEl.className="toast show"+(bad?" bad":"");clearTimeout(toastTimer);toastTimer=setTimeout(()=>toastEl.className="toast",2600)}

async function api(path,method="GET",body){
  const o={method,cache:"no-store",headers:{Authorization:"Bearer "+key}};
  if(body){o.headers["Content-Type"]="application/json";o.body=JSON.stringify(body)}
  let r;try{r=await fetch(path,o)}catch{throw Error("Pas de réseau")}
  const d=await r.json().catch(()=>({}));
  if(r.status===401){const e=Error("Clé refusée");e.un=true;throw e}
  if(!r.ok)throw Error(d.error||"Action impossible");
  return d;
}
// Action riche vers le PC. Lève si le PC est hors ligne / pont muet.
async function act(action,args,quiet){
  if(!quiet)setBusy(true);
  try{return await api("/api/action","POST",{action,args:args||{}})}
  catch(e){if(e.un)return lock("Clé refusée");if(!quiet)toast(e.message,true);throw e}
  finally{if(!quiet)setBusy(false)}
}

function lock(reason){stopStream();localStorage.removeItem(KEY);key="";app.hidden=true;gate.hidden=false;field.value="";gateErr.textContent=reason||"";setTimeout(()=>field.focus(),0)}
function unlock(v){key=(v||"").trim();if(!key){gateErr.textContent="Saisis la clé.";return}localStorage.setItem(KEY,key);gate.hidden=true;app.hidden=false;start()}

/* ---------- Statut temps réel (SSE) ---------- */
function start(){refresh();connectStream();switchTab(tab)}
async function refresh(){try{apply(await api("/api/status"))}catch(e){if(e.un)lock(e.message)}}
function connectStream(){
  if(stream)return;
  const ctrl=new AbortController();streamStop=()=>ctrl.abort();
  fetch("/api/events",{cache:"no-store",headers:{Authorization:"Bearer "+key},signal:ctrl.signal}).then(async r=>{
    if(r.status===401)return lock("Clé refusée");
    if(!r.ok||!r.body)throw 0;
    stream=r;const rd=r.body.getReader(),dec=new TextDecoder();let buf="";
    while(true){const p=await rd.read();if(p.done)break;buf+=dec.decode(p.value,{stream:true});let i;
      while((i=buf.indexOf("\n\n"))>=0){const f=buf.slice(0,i);buf=buf.slice(i+2);const l=f.split("\n").find(x=>x.startsWith("data: "));if(l){try{apply(JSON.parse(l.slice(6)))}catch{}}}}
  }).catch(()=>{}).finally(()=>{stream=null;if(key&&!document.hidden)setTimeout(connectStream,2000)});
}
function stopStream(){if(streamStop)streamStop();stream=null}

function apply(d){data=d;const pc=d.pc||null,on=!!d.online,ready=!!d.control_ready;
  $("#device").textContent=pc?.computer||"GTOL";
  const dot=$("#hdot");dot.className="dot "+(ready?"on":on?"warn":"off");
  $("#hstate").textContent=ready?"En ligne":on?"Pont muet":"Éteinte";
  if(tab==="home")renderHome(d);
}

/* ---------- Onglet Accueil ---------- */
function metric(id,val,pct,hot){const e=$("#m_"+id);if(!e)return;e.querySelector(".val").textContent=val;const b=e.querySelector("i");if(b){b.style.width=(Number.isFinite(pct)?clamp(pct,0,100):0)+"%";b.classList.toggle("hot",!!hot)}}
function renderHome(d){
  const pc=d.pc||{},on=!!d.online,ready=!!d.control_ready;
  $("#homeMsg").textContent=d.message||(on?"Tour en ligne":"Tour éteinte");
  $("#homeMsg").previousElementSibling.className="dot "+(ready?"on":on?"warn":"off");
  metric("cpu",Number.isFinite(pc.cpu_load_percent)?pc.cpu_load_percent+"%":"—",pc.cpu_load_percent);
  metric("gpu",Number.isFinite(pc.gpu_load_percent)?pc.gpu_load_percent+"%":"—",pc.gpu_load_percent);
  metric("temp",Number.isFinite(pc.gpu_temperature_c)?pc.gpu_temperature_c+"°":"—",pc.gpu_temperature_c,pc.gpu_temperature_c>=82);
  metric("ram",Number.isFinite(pc.memory_free_gb)?pc.memory_free_gb+" Go":"—",pc.memory_used_percent);
  metric("disk",Number.isFinite(pc.disk_free_gb)?pc.disk_free_gb+" Go":"—",pc.disk_used_percent,pc.disk_used_percent>=92);
  metric("up",pc.uptime_minutes!=null?fmtDur(pc.uptime_minutes):"—",0);
  $("#wakeBtn").hidden=on;$("#lockBtn").hidden=!on;
  const nightOn=pc.mode==="night";
  $("#modeNormal").classList.toggle("active",pc.mode==="normal");
  $("#modeNight").classList.toggle("active",nightOn);
  document.querySelectorAll("[data-need-on]").forEach(b=>b.disabled=!on);
}

/* ---------- Onglet Écran ---------- */
function screenWidth(){const w=$("#screenImg")?.clientWidth||$("#screenWrap").clientWidth||720;return clamp(Math.round(w*(window.devicePixelRatio||1)),640,1920)}
async function grabScreen(quiet){
  if(!data?.online){$("#screenPh").textContent="Tour éteinte";return}
  try{
    const r=await act("Screenshot",{monitor:lastMonitor,width:screenWidth()},quiet);
    if(!r?.image)return;
    const img=$("#screenImg");img.src="data:image/jpeg;base64,"+r.image;img.hidden=false;$("#screenPh").hidden=true;
    if(Array.isArray(r.monitors)&&r.monitors.length!==monitors.length){monitors=r.monitors;renderMonitors()}
    else if(Array.isArray(r.monitors))monitors=r.monitors;
  }catch{}
}
function renderMonitors(){
  const box=$("#monitorSel");box.innerHTML="";
  if(monitors.length<=1){box.hidden=true;return}
  box.hidden=false;
  const mk=(label,idx)=>{const b=document.createElement("button");b.textContent=label;b.className=lastMonitor===idx?"active":"";b.onclick=()=>{lastMonitor=idx;renderMonitors();grabScreen()};return b};
  box.appendChild(mk("Tous",-1));
  monitors.forEach((m,i)=>box.appendChild(mk("É"+(i+1)+(m.primary?"*":""),i)));
}
function screenTap(ev,longpress){
  const img=$("#screenImg");if(img.hidden||!data?.online)return;
  const rect=img.getBoundingClientRect();
  const nx=clamp((ev.clientX-rect.left)/rect.width,0,1),ny=clamp((ev.clientY-rect.top)/rect.height,0,1);
  const mark=document.createElement("div");mark.className="tap";mark.style.left=(ev.clientX-rect.left)+"px";mark.style.top=(ev.clientY-rect.top)+"px";
  $("#screenWrap").appendChild(mark);setTimeout(()=>mark.remove(),400);vibe();
  const button=longpress?"right":clickMode;const dbl=clickMode==="double"&&!longpress;
  act("Click",{monitor:lastMonitor,nx,ny,button:button==="double"?"left":button,double:dbl},true).then(()=>setTimeout(()=>grabScreen(true),160)).catch(()=>{});
}
function startScreenAuto(){stopScreenAuto();if(!screenAuto)return;const loop=async()=>{if(tab!=="screen"||!screenAuto)return;await grabScreen(true);screenTimer=setTimeout(loop,1300)};screenTimer=setTimeout(loop,1300)}
function stopScreenAuto(){clearTimeout(screenTimer);screenTimer=0}

/* ---------- Onglet Fichiers ---------- */
async function loadDir(path){
  filePath=path;setBusy(true);
  try{const r=await act("FsList",{path},true);renderDir(r)}
  catch(e){$("#fileList").innerHTML='<p class="empty">'+esc(e.message)+"</p>"}
  finally{setBusy(false)}
}
function renderDir(r){
  const list=$("#fileList");list.innerHTML="";
  $("#crumb").innerHTML=r.is_root?"<b>Disques</b>":crumbHtml(r.path);
  $("#fileUp").disabled=r.is_root;
  $("#fileActions").hidden=r.is_root;
  if(!r.entries||!r.entries.length){list.innerHTML='<p class="empty">Dossier vide</p>';return}
  for(const e of r.entries){
    const b=document.createElement("button");b.className="item";
    const ic=e.dir?"▸":fileIcon(e.name);
    const size=e.dir?"":humanSize(e.size);
    b.innerHTML=`<span class="ic">${e.dir?"📁":"📄"}</span><span class="nm"><b>${esc(e.name)}</b><span>${size}</span></span><span class="go">${e.dir?"›":"⋯"}</span>`;
    b.onclick=()=>e.dir?loadDir(e.path):fileMenu(e);
    list.appendChild(b);
  }
}
function crumbHtml(p){const parts=p.replace(/\\+$/,"").split("\\");return parts.map((s,i)=>i===parts.length-1?`<b>${esc(s||p)}</b>`:esc(s)).join(" \\ ")}
function fileIcon(n){return"📄"}
function humanSize(b){if(b==null)return"";if(b<1024)return b+" o";if(b<1048576)return(b/1024).toFixed(0)+" Ko";if(b<1073741824)return(b/1048576).toFixed(1)+" Mo";return(b/1073741824).toFixed(2)+" Go"}
async function fileMenu(e){
  const choice=await pickAction(e.name,[
    ["Aperçu texte","view"],["Télécharger","download"],["Ouvrir sur le PC","open"],["Supprimer","delete"]
  ]);
  if(choice==="view")return viewFile(e);
  if(choice==="download")return downloadFile(e);
  if(choice==="open")return act("OpenPath",{path:e.path}).then(r=>toast(r.message||"Ouvert")).catch(()=>{});
  if(choice==="delete"){if(await confirmDlg("Supprimer ?",e.name)){await act("FsDelete",{path:e.path}).then(()=>{toast("Supprimé");loadDir(filePath)}).catch(()=>{})}}
}
async function viewFile(e){
  try{const r=await act("FsRead",{path:e.path});textDlg(e.name,r.text)}
  catch(err){toast(err.message,true)}
}
async function downloadFile(e){
  try{const r=await act("FsDownload",{path:e.path});const bin=atob(r.content_base64);const arr=new Uint8Array(bin.length);for(let i=0;i<bin.length;i++)arr[i]=bin.charCodeAt(i);
    const url=URL.createObjectURL(new Blob([arr]));const a=document.createElement("a");a.href=url;a.download=r.name;a.click();setTimeout(()=>URL.revokeObjectURL(url),1500);toast("Téléchargé")}
  catch(err){toast(err.message,true)}
}
async function uploadFile(fileObj){
  const buf=await fileObj.arrayBuffer();
  if(buf.byteLength>1200000)return toast("Fichier trop lourd (max ~1 Mo)",true);
  let bin="";const arr=new Uint8Array(buf);for(let i=0;i<arr.length;i++)bin+=String.fromCharCode(arr[i]);
  const b64=btoa(bin);const target=(filePath.replace(/\\+$/,""))+"\\"+fileObj.name;
  await act("FsWrite",{path:target,content_base64:b64}).then(()=>{toast("Envoyé");loadDir(filePath)}).catch(()=>{});
}

/* ---------- Onglet Système ---------- */
async function loadSystem(){
  try{
    const [proc,drives,info]=await Promise.all([act("Processes",null,true),act("Drives",null,true),act("SessionInfo",null,true).catch(()=>null)]);
    renderProc(proc.processes||[]);renderDrives(drives.drives||[]);renderApps(info?.apps||[]);
  }catch(e){if(e.un)lock(e.message)}
}
function renderProc(list){
  const box=$("#procList");box.innerHTML="";
  if(!list.length){box.innerHTML='<p class="empty">—</p>';return}
  list.slice(0,20).forEach(p=>{
    const row=document.createElement("div");row.className="proc";
    row.innerHTML=`<span class="nm"><b>${esc(p.name)}</b><span>${esc(p.window||"pid "+p.pid)}</span></span><span class="mem">${p.memory_mb} Mo</span>`;
    const k=document.createElement("button");k.className="btn bad sm";k.textContent="Kill";k.style.width="auto";
    k.onclick=async()=>{if(await confirmDlg("Arrêter ?",p.name)){await act("KillProcess",{pid:p.pid}).then(r=>{toast(r.message||"Arrêté");loadSystem()}).catch(()=>{})}};
    row.appendChild(k);box.appendChild(row);
  });
}
function renderDrives(list){
  const box=$("#driveList");box.innerHTML="";
  list.forEach(d=>{const row=document.createElement("div");row.className="kv";
    row.innerHTML=`<span>${esc(d.name)} ${esc(d.label||d.type)}</span><b>${d.free_gb} / ${d.size_gb} Go · ${d.used_percent}%</b>`;box.appendChild(row)});
}
const APP_IC={chrome:"🌐",edge:"🌐",explorer:"🗂️",notepad:"📝",terminal:"⌨️",taskmgr:"📊",parsec:"🖥️",spotify:"🎵",steam:"🎮",discord:"💬",vscode:"🧩",fancontrol:"🌀"};
function renderApps(list){
  const box=$("#appList");box.innerHTML="";
  if(!list.length){box.innerHTML='<p class="empty">Agent de session requis</p>';return}
  list.forEach(a=>{const b=document.createElement("button");b.innerHTML=`<span class="ap-ic">${APP_IC[a.id]||"▶"}</span><span>${esc(a.name)}</span>`;
    b.onclick=()=>act("Launch",{app:a.id}).then(r=>toast(r.message||"Lancé")).catch(()=>{});box.appendChild(b)});
}

/* ---------- Onglet Terminal ---------- */
let termShell="powershell";
function termWrite(html){const t=$("#termOut");t.insertAdjacentHTML("beforeend",html);t.scrollTop=t.scrollHeight}
async function runCmd(cmd){
  if(!cmd.trim())return;
  termWrite(`<div class="cmd">${termShell==="cmd"?">":"PS>"} ${esc(cmd)}</div>`);
  setBusy(true);
  try{const r=await act("Exec",{command:cmd,shell:termShell},true);
    if(r.stdout)termWrite(`<div>${esc(r.stdout)}</div>`);
    if(r.stderr)termWrite(`<div class="err">${esc(r.stderr)}</div>`);
    termWrite(`<div class="ok">— code ${r.exit_code}</div>`);
  }catch(e){termWrite(`<div class="err">${esc(e.message)}</div>`)}
  finally{setBusy(false)}
}

/* ---------- Navigation ---------- */
function switchTab(name){
  tab=name;
  document.querySelectorAll(".view").forEach(v=>v.hidden=v.id!=="view-"+name);
  document.querySelectorAll(".nav button").forEach(b=>b.classList.toggle("active",b.dataset.tab===name));
  stopScreenAuto();
  if(name==="home")renderHome(data||{});
  if(name==="screen"){grabScreen();startScreenAuto()}
  if(name==="files"&&!filePath)loadDir("");
  else if(name==="files")loadDir(filePath);
  if(name==="system")loadSystem();
  if(name==="terminal")setTimeout(()=>$("#termIn").focus(),100);
  window.scrollTo(0,0);
}

/* ---------- Dialogues ---------- */
const dlg=$("#dlg");let dlgResolve=null;
function closeDlg(v){if(dlgResolve){const r=dlgResolve;dlgResolve=null;r(v)}dlg.close()}
function confirmDlg(title,text){return new Promise(res=>{dlgResolve=res;$("#dlgBody").innerHTML=`<h3>${esc(title)}</h3><p>${esc(text)}</p><div class="row two"><button class="btn" id="dlgNo">Annuler</button><button class="btn bad" id="dlgYes">Confirmer</button></div>`;dlg.showModal();$("#dlgNo").onclick=()=>closeDlg(false);$("#dlgYes").onclick=()=>closeDlg(true)})}
function pickAction(title,options){return new Promise(res=>{dlgResolve=res;const btns=options.map(([l,v])=>`<button class="btn" data-v="${v}">${esc(l)}</button>`).join("");$("#dlgBody").innerHTML=`<h3>${esc(title)}</h3><div class="row">${btns}<button class="btn" data-v="">Fermer</button></div>`;dlg.showModal();$("#dlgBody").querySelectorAll("[data-v]").forEach(b=>b.onclick=()=>closeDlg(b.dataset.v||null))})}
function textDlg(title,text){dlgResolve=null;$("#dlgBody").innerHTML=`<h3>${esc(title)}</h3><textarea readonly>${esc(text)}</textarea><button class="btn" id="dlgClose">Fermer</button>`;dlg.showModal();$("#dlgClose").onclick=()=>dlg.close()}
dlg.addEventListener("cancel",()=>{if(dlgResolve)closeDlg(null)});

/* ---------- Init & liaisons ---------- */
$("#unlock").addEventListener("submit",e=>{e.preventDefault();unlock(field.value)});
$("#refreshBtn").addEventListener("click",()=>{vibe();refresh();if(tab==="screen")grabScreen();if(tab==="system")loadSystem()});
document.querySelectorAll(".nav button").forEach(b=>b.addEventListener("click",()=>{vibe();switchTab(b.dataset.tab)}));

// Accueil : actions
function bindAction(id,action,args,confirmTxt){const el=$("#"+id);if(!el)return;el.addEventListener("click",async()=>{vibe();if(confirmTxt&&!(await confirmDlg(el.textContent.trim(),confirmTxt)))return;act(action,args).then(r=>{toast(r.message||"OK");setTimeout(refresh,400)}).catch(()=>{})})}
$("#wakeBtn").addEventListener("click",async()=>{vibe();try{const r=await api("/api/wake","POST");toast(r.message||"Signal envoyé");setTimeout(refresh,1500)}catch(e){if(e.un)lock(e.message);else toast(e.message,true)}});
bindAction("lockBtn","Lock");
async function legacy(action,confirmTxt,label){vibe();if(confirmTxt&&!(await confirmDlg(label,confirmTxt)))return;setBusy(true);try{const r=await api("/api/control","POST",{action});toast(r.message||"OK");setTimeout(refresh,600)}catch(e){if(e.un)lock(e.message);else toast(e.message,true)}finally{setBusy(false)}}
$("#shareParsec").addEventListener("click",()=>legacy("share-parsec"));
$("#modeNormal").addEventListener("click",()=>legacy("normal"));
$("#modeNight").addEventListener("click",()=>legacy("night"));
$("#repairFans").addEventListener("click",()=>legacy("repair-fans"));
$("#launchCodex").addEventListener("click",()=>legacy("launch-codex"));
$("#rebootBtn").addEventListener("click",()=>legacy("reboot","Windows redémarre. Parsec sera coupé un instant.","Redémarrer"));
$("#hibernateBtn").addEventListener("click",()=>legacy("hibernate","Windows s'éteint. Le réveil Wake-on-LAN reste possible.","Éteindre"));
bindAction("displaysOff","DisplaysOff");
bindAction("displaysOn","DisplaysOn");

// Écran : contrôles
let pressTimer=0,pressed=false;
const wrap=$("#screenWrap");
wrap.addEventListener("pointerdown",e=>{pressed=false;pressTimer=setTimeout(()=>{pressed=true;screenTap(e,true)},500)});
wrap.addEventListener("pointerup",e=>{clearTimeout(pressTimer);if(!pressed)screenTap(e,false)});
wrap.addEventListener("pointercancel",()=>clearTimeout(pressTimer));
document.querySelectorAll("[data-click]").forEach(b=>b.addEventListener("click",()=>{vibe();clickMode=b.dataset.click;document.querySelectorAll("[data-click]").forEach(x=>x.classList.toggle("active",x===b))}));
$("#autoScreen").addEventListener("click",()=>{screenAuto=!screenAuto;$("#autoScreen").classList.toggle("active",screenAuto);$("#autoScreen").textContent=screenAuto?"Auto ●":"Auto ○";if(screenAuto)startScreenAuto();else stopScreenAuto()});
$("#shotBtn").addEventListener("click",()=>{vibe();grabScreen()});
$("#keyText").addEventListener("keydown",e=>{if(e.key==="Enter"){e.preventDefault();sendText(true)}});
$("#keySend").addEventListener("click",()=>sendText(false));
function sendText(enter){const v=$("#keyText").value;if(!v&&!enter)return;act("TypeText",{text:v,enter},true).then(()=>{$("#keyText").value="";setTimeout(()=>grabScreen(true),200)}).catch(()=>{})}
document.querySelectorAll("[data-key]").forEach(b=>b.addEventListener("click",()=>{vibe();const mods=b.dataset.mods?b.dataset.mods.split(","):[];act("SendKey",{key:b.dataset.key,modifiers:mods},true).then(()=>setTimeout(()=>grabScreen(true),160)).catch(()=>{})}));
document.querySelectorAll("[data-scroll]").forEach(b=>b.addEventListener("click",()=>{vibe();act("Scroll",{amount:parseInt(b.dataset.scroll,10)},true).then(()=>setTimeout(()=>grabScreen(true),160)).catch(()=>{})}));
document.querySelectorAll("[data-media]").forEach(b=>b.addEventListener("click",()=>{vibe();act("Media",{command:b.dataset.media},true).then(r=>toast(r.message||"OK")).catch(()=>{})}));
const volRange=$("#volRange");let volTimer=0;
volRange.addEventListener("input",()=>{$("#volVal").textContent=volRange.value+"%";clearTimeout(volTimer);volTimer=setTimeout(()=>act("Volume",{level:parseInt(volRange.value,10)},true).catch(()=>{}),120)});

// Fichiers
$("#fileUp").addEventListener("click",()=>{if(data){}loadDir(parentPath(filePath))});
function parentPath(p){const q=p.replace(/\\+$/,"");const i=q.lastIndexOf("\\");return i<=1?"":q.slice(0,i>2?i:3)}
$("#fileRefresh").addEventListener("click",()=>loadDir(filePath));
$("#newFolder").addEventListener("click",async()=>{const name=await promptDlg("Nouveau dossier","Nom");if(name){const target=filePath.replace(/\\+$/,"")+"\\"+name;await act("FsMkdir",{path:target}).then(()=>{toast("Créé");loadDir(filePath)}).catch(()=>{})}});
$("#uploadInput").addEventListener("change",e=>{const f=e.target.files[0];if(f)uploadFile(f);e.target.value=""});
function promptDlg(title,label){return new Promise(res=>{dlgResolve=res;$("#dlgBody").innerHTML=`<h3>${esc(title)}</h3><input id="dlgInput" placeholder="${esc(label)}" autocomplete="off"><div class="row two"><button class="btn" id="dlgNo">Annuler</button><button class="btn pri" id="dlgYes">OK</button></div>`;dlg.showModal();setTimeout(()=>$("#dlgInput").focus(),50);$("#dlgNo").onclick=()=>closeDlg(null);$("#dlgYes").onclick=()=>closeDlg($("#dlgInput").value.trim()||null)})}

// Système
$("#sysRefresh").addEventListener("click",()=>{vibe();loadSystem()});

// Terminal
document.querySelectorAll("[data-shell]").forEach(b=>b.addEventListener("click",()=>{termShell=b.dataset.shell;document.querySelectorAll("[data-shell]").forEach(x=>x.classList.toggle("active",x===b))}));
$("#termForm").addEventListener("submit",e=>{e.preventDefault();const v=$("#termIn").value;$("#termIn").value="";runCmd(v)});
$("#termClear").addEventListener("click",()=>$("#termOut").innerHTML="");

document.addEventListener("visibilitychange",()=>{if(document.hidden){stopStream();stopScreenAuto()}else if(key){connectStream();refresh();if(tab==="screen"){grabScreen();startScreenAuto()}}});
const hashKey=new URLSearchParams(location.hash.slice(1)).get("k");if(hashKey?.trim()){key=hashKey.trim();localStorage.setItem(KEY,key);history.replaceState(null,"",location.pathname)}
navigator.storage?.persist?.().catch(()=>{});
navigator.serviceWorker?.register("/sw.js",{updateViaCache:"none"}).catch(()=>{});
if(key){gate.hidden=true;app.hidden=false;start()}else field.focus();
})();
"""

BODY = r"""
<div class="busy" id="busy"></div>
<div class="toast" id="toast"></div>

<main class="gate" id="gate">
  <div class="box">
    <div class="logo">GT</div>
    <h1>PC Control</h1>
    <p>Pilotage privé de la tour GTOL.</p>
    <form id="unlock" novalidate>
      <input id="key" type="password" autocomplete="current-password" spellcheck="false" autocapitalize="off" enterkeyhint="go" placeholder="Clé d'accès">
      <button class="btn pri" type="submit" style="min-height:52px">Entrer</button>
      <p class="err" id="gateErr" role="alert"></p>
    </form>
  </div>
</main>

<main class="app" id="app" hidden>
  <header class="top">
    <div class="brand"><span class="logo">GT</span><span><b id="device">GTOL</b><small>PC Control</small></span></div>
    <div class="top-right">
      <span class="stat"><span class="dot" id="hdot"></span><span id="hstate">…</span></span>
      <button class="iconbtn" id="refreshBtn" aria-label="Actualiser">↻</button>
    </div>
  </header>

  <!-- Accueil -->
  <section class="view" id="view-home">
    <div class="card"><div class="card-b"><p class="msg"><span class="dot"></span><span id="homeMsg">Lecture…</span></p></div></div>
    <div class="card"><div class="card-b flush"><div class="grid">
      <div class="cell" id="m_cpu"><span class="k">CPU</span><span class="val">—</span><span class="bar"><i></i></span></div>
      <div class="cell" id="m_gpu"><span class="k">GPU</span><span class="val">—</span><span class="bar"><i></i></span></div>
      <div class="cell" id="m_temp"><span class="k">Temp GPU</span><span class="val">—</span><span class="bar"><i></i></span></div>
      <div class="cell" id="m_ram"><span class="k">RAM libre</span><span class="val">—</span><span class="bar"><i></i></span></div>
      <div class="cell" id="m_disk"><span class="k">Disque C</span><span class="val">—</span><span class="bar"><i></i></span></div>
      <div class="cell" id="m_up"><span class="k">Uptime</span><span class="val">—</span><span class="bar"><i></i></span></div>
    </div></div></div>
    <div class="card"><div class="card-h"><h2>Contrôle rapide</h2></div><div class="card-b"><div class="row">
      <button class="btn pri" id="wakeBtn">Allumer la tour</button>
      <button class="btn" id="lockBtn" data-need-on hidden>Verrouiller la session</button>
      <button class="btn" id="shareParsec" data-need-on>Partager Parsec</button>
      <div class="seg"><button id="modeNormal" data-need-on>Normal</button><button id="modeNight" data-need-on>Nuit</button></div>
      <div class="row two"><button class="btn sm" id="displaysOff" data-need-on>Écrans off</button><button class="btn sm" id="displaysOn" data-need-on>Écrans on</button></div>
      <div class="row two"><button class="btn sm" id="repairFans" data-need-on>Ventilateurs</button><button class="btn sm" id="launchCodex" data-need-on>Lancer Codex</button></div>
    </div></div></div>
    <div class="card"><div class="card-h"><h2>Alimentation</h2><span class="sub">Confirmation requise</span></div><div class="card-b"><div class="row two">
      <button class="btn" id="rebootBtn" data-need-on>Redémarrer</button>
      <button class="btn bad" id="hibernateBtn" data-need-on>Éteindre</button>
    </div></div></div>
    <div class="card"><div class="card-b"><button class="btn sm" onclick="localStorage.removeItem('pcControlKey');location.reload()" style="border:0;color:var(--faint)">Oublier la clé</button></div></div>
  </section>

  <!-- Écran -->
  <section class="view" id="view-screen" hidden>
    <div class="card"><div class="card-b flush">
      <div class="screen-wrap" id="screenWrap"><img id="screenImg" hidden alt="Écran de la tour"><div class="ph" id="screenPh">Capture…</div><div class="screen-hint">Tape pour cliquer · appui long = clic droit</div></div>
    </div></div>
    <div class="row three"><div class="seg" style="grid-template-columns:1fr 1fr 1fr"><button data-click="left" class="active">Gauche</button><button data-click="right">Droit</button><button data-click="double">Double</button></div></div>
    <div class="row two"><button class="btn sm" id="shotBtn">Rafraîchir</button><button class="btn sm" id="autoScreen">Auto ○</button></div>
    <div class="card"><div class="card-h"><h2>Clavier</h2><span class="sub" id="monitorSel" style="display:flex;gap:4px" hidden></span></div><div class="card-b">
      <div class="keybar"><input id="keyText" placeholder="Texte à saisir…" autocomplete="off" autocapitalize="off" spellcheck="false" enterkeyhint="send"><button class="btn sm" id="keySend" style="width:auto">Envoyer</button></div>
      <div class="keys" style="margin-top:10px">
        <button data-key="enter">⏎</button><button data-key="backspace">⌫</button><button data-key="tab">⇥</button><button data-key="escape">esc</button><button data-key="up">↑</button><button data-key="down">↓</button>
        <button data-key="left">←</button><button data-key="right">→</button><button data-key="c" data-mods="ctrl">^C</button><button data-key="v" data-mods="ctrl">^V</button><button data-key="win">⊞</button><button data-key="delete">del</button>
      </div>
    </div></div>
    <div class="card"><div class="card-h"><h2>Défilement & son</h2></div><div class="card-b">
      <div class="row two" style="margin-bottom:12px"><button class="btn sm" data-scroll="600">▲ Haut</button><button class="btn sm" data-scroll="-600">▼ Bas</button></div>
      <div class="vol"><span class="sub">VOL</span><input type="range" id="volRange" min="0" max="100" value="50"><span class="val" id="volVal">—</span></div>
      <div class="row three" style="margin-top:12px"><button class="btn sm" data-media="prev">⏮</button><button class="btn sm" data-media="playpause">⏯</button><button class="btn sm" data-media="next">⏭</button></div>
    </div></div>
  </section>

  <!-- Fichiers -->
  <section class="view" id="view-files" hidden>
    <div class="card"><div class="crumb" id="crumb"><b>Disques</b></div>
      <div class="card-b" id="fileActions" hidden style="display:flex;gap:8px;flex-wrap:wrap">
        <button class="btn sm" id="fileUp" style="width:auto">↑ Parent</button>
        <button class="btn sm" id="fileRefresh" style="width:auto">↻</button>
        <button class="btn sm" id="newFolder" style="width:auto">+ Dossier</button>
        <label class="btn sm" style="width:auto;cursor:pointer">↥ Envoyer<input type="file" id="uploadInput" hidden></label>
      </div>
      <div class="list" id="fileList"></div>
    </div>
  </section>

  <!-- Système -->
  <section class="view" id="view-system" hidden>
    <div class="card"><div class="card-h"><h2>Applications</h2></div><div class="card-b"><div class="apps" id="appList"></div></div></div>
    <div class="card"><div class="card-h"><h2>Disques</h2></div><div class="card-b" id="driveList"></div></div>
    <div class="card"><div class="card-h"><h2>Processus</h2><button class="btn sm" id="sysRefresh" style="width:auto">↻</button></div><div class="card-b flush" id="procList"></div></div>
  </section>

  <!-- Terminal -->
  <section class="view" id="view-terminal" hidden>
    <div class="card"><div class="card-h"><h2>Terminal</h2><div class="seg" style="grid-template-columns:1fr 1fr;width:150px"><button data-shell="powershell" class="active">PS</button><button data-shell="cmd">CMD</button></div></div>
      <div class="card-b">
        <pre class="term" id="termOut"></pre>
        <form id="termForm" class="term-in"><input id="termIn" placeholder="Commande…" autocomplete="off" autocapitalize="off" spellcheck="false" enterkeyhint="go"><button class="btn pri" type="submit" style="width:auto">Run</button></form>
        <button class="btn sm" id="termClear" style="margin-top:8px">Effacer</button>
      </div>
    </div>
  </section>

  <nav class="nav">
    <button data-tab="home" class="active"><span class="ni">▦</span>Accueil</button>
    <button data-tab="screen"><span class="ni">▣</span>Écran</button>
    <button data-tab="files"><span class="ni">🗂</span>Fichiers</button>
    <button data-tab="system"><span class="ni">⚙</span>Système</button>
    <button data-tab="terminal"><span class="ni">›_</span>Terminal</button>
  </nav>
</main>

<dialog id="dlg"><div class="dlg" id="dlgBody"></div></dialog>
"""

PAGE = """<!doctype html><html lang="fr"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover,maximum-scale=1">
<meta name="theme-color" content="#0a0a0b"><meta name="color-scheme" content="dark">
<meta name="mobile-web-app-capable" content="yes"><meta name="apple-mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent"><meta name="apple-mobile-web-app-title" content="PC Control">
<link rel="manifest" href="/manifest.webmanifest?v=9"><link rel="icon" type="image/svg+xml" href="/icon.svg?v=9"><link rel="apple-touch-icon" href="/icon-192.png?v=9">
<title>PC Control</title><style>__STYLE__</style></head><body>
<noscript><main style="padding:24px"><h1>PC Control</h1><p>JavaScript requis.</p></main></noscript>
__BODY__<script>__SCRIPT__</script></body></html>""".replace("__STYLE__", STYLE).replace("__BODY__", BODY).replace("__SCRIPT__", SCRIPT)

MANIFEST = {
    "name": "GTOL PC Control",
    "short_name": "PC Control",
    "description": "Pilotage complet et privé de la tour GTOL",
    "id": "/",
    "start_url": "/?app=9",
    "scope": "/",
    "display": "standalone",
    "display_override": ["standalone", "minimal-ui"],
    "orientation": "portrait",
    "background_color": "#0a0a0b",
    "theme_color": "#0a0a0b",
    "categories": ["utilities", "productivity"],
    "icons": [
        {"src": "/icon-192.png?v=9", "sizes": "192x192", "type": "image/png", "purpose": "any"},
        {"src": "/icon-512.png?v=9", "sizes": "512x512", "type": "image/png", "purpose": "any"},
        {"src": "/icon-512.png?v=9", "sizes": "512x512", "type": "image/png", "purpose": "maskable"},
    ],
    "shortcuts": [
        {"name": "Écran", "short_name": "Écran", "url": "/?app=9#screen"},
        {"name": "Terminal", "short_name": "Terminal", "url": "/?app=9#terminal"},
    ],
}

SERVICE_WORKER = r"""const CACHE="pc-control-v9",OFFLINE="/?offline=9";
self.addEventListener("install",e=>{self.skipWaiting()});
self.addEventListener("activate",e=>e.waitUntil(caches.keys().then(k=>Promise.all(k.map(x=>caches.delete(x)))).then(()=>self.clients.claim())));
self.addEventListener("fetch",e=>{const r=e.request,u=new URL(r.url);if(r.method!=="GET"||u.pathname.startsWith("/api/"))return;
 e.respondWith(fetch(r,{cache:"no-store"}).catch(()=>caches.match(r).then(x=>x||new Response("Hors connexion",{status:503,headers:{"Content-Type":"text/plain;charset=utf-8"}}))))});
"""
