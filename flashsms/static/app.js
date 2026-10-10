(function(){const ta=document.getElementById('msg'),cc=document.getElementById('charcount');if(!ta||!cc)return;
const valEl=cc.querySelector('.cc-val'),encEl=cc.querySelector('.cc-enc'),partsEl=cc.querySelector('.cc-parts');
const B=new Set("@£$¥èéùìòÇ\nØø\rÅåΔ_ΦΓΛΩΠΨΣΘΞÆæßÉ !\"#¤%&'()*+,-./0123456789:;<=>?¡ABCDEFGHIJKLMNOPQRSTUVWXYZÄÖÑÜ§¿abcdefghijklmnopqrstuvwxyzäöñüà");
const E=new Set("^{}\\[~]|€");
function P(n,s,m){return n<=s?1:1+Math.ceil((n-s)/m)}
function C(t){let c=0;for(const ch of t){if(B.has(ch))c+=1;else if(E.has(ch))c+=2;else return{enc:'UCS-2',chars:t.length,parts:P(t.length,70,67),per:70}}return{enc:'GSM-7',chars:c,parts:P(c,160,153),per:160}}
function U(){const r=C(ta.value);encEl.textContent=r.enc;valEl.textContent=r.chars+' / '+r.per;partsEl.textContent=r.parts+' SMS';valEl.classList.toggle('over',r.parts>1)}
ta.addEventListener('input',U);U()})();

(function(){const dz=document.getElementById('dropzone'),input=document.getElementById('csv'),fileEl=document.getElementById('dz-file'),preview=document.getElementById('preview'),pvV=document.getElementById('pv-valid'),pvI=document.getElementById('pv-invalid'),pvS=document.getElementById('pv-sample');
if(!dz||!input)return;
const D=new Set([11,12,13,14,15,16,17,18,19,21,22,24,27,28,31,32,33,34,35,37,38,41,42,43,44,45,46,47,48,49,51,53,54,55,61,62,63,64,65,66,67,68,69,71,73,74,75,77,79,81,82,83,84,85,86,87,88,89,91,92,93,94,95,96,97,98,99]);
function n(raw){let d=String(raw||'').replace(/\D/g,'');if(!d)return null;if(d.startsWith('0'))d=d.slice(1);if(!d.startsWith('55'))d='55'+d;if(d.length!==13)return null;if(!D.has(parseInt(d.slice(2,4),10)))return null;if(d[4]!=='9')return null;return d}
function pL(l){for(const p of l.split(/[;,]/).map(s=>s.trim())){const x=n(p);if(x)return x}return null}
function A(f){fileEl.textContent=f.name;const r=new FileReader();r.onload=e=>{const t=e.target.result.replace(/^\uFEFF/,''),ls=t.split(/\r?\n/).filter(l=>l.trim()),v=new Set();let inv=0,hs=false;
for(const l of ls){if(!hs&&/numero|phone|telefone|number/i.test(l)&&!/\d{10,}/.test(l)){hs=true;continue}const x=pL(l);if(x)v.add(x);else inv++}
pvV.textContent=v.size;pvI.textContent=inv;const a=[...v].slice(0,5);pvS.textContent=a.length?a.join(' · ')+(v.size>5?' …':''):'';preview.hidden=false};r.readAsText(f)}
dz.addEventListener('click',()=>input.click());
input.addEventListener('change',e=>{if(e.target.files[0])A(e.target.files[0])});
['dragenter','dragover'].forEach(ev=>dz.addEventListener(ev,e=>{e.preventDefault();dz.classList.add('dragover')}));
['dragleave','drop'].forEach(ev=>dz.addEventListener(ev,e=>{e.preventDefault();dz.classList.remove('dragover')}));
dz.addEventListener('drop',e=>{const f=e.dataTransfer.files[0];if(f){const dt=new DataTransfer();dt.items.add(f);input.files=dt.files;A(f)}})})();

(function(){const h=document.querySelector('.camp-header');if(!h)return;const cid=h.dataset.cid;
const bar=document.getElementById('prog-bar'),t=document.getElementById('cs-total'),s=document.getElementById('cs-sent'),f=document.getElementById('cs-failed'),p=document.getElementById('cs-pending'),st=document.getElementById('camp-status');
let rl=false;
async function poll(){try{const r=await fetch(`/api/campaigns/${cid}/stats`);if(!r.ok)return;const d=await r.json();
const done=(d.sent||0)+(d.failed||0),pct=d.total?(done/d.total*100):0;
bar.style.width=pct+'%';t.textContent=d.total;s.textContent=d.sent;f.textContent=d.failed;p.textContent=d.pending;
st.textContent=d.status;st.className='badge badge-'+d.status;
if(!rl&&['done','cancelled','failed'].includes(d.status)){rl=true;setTimeout(()=>location.reload(),1200)}}catch(_){}}
poll();setInterval(poll,3000);
const fs=document.querySelectorAll('.filter'),rs=document.querySelectorAll('tbody tr[data-status]');
fs.forEach(b=>b.addEventListener('click',()=>{fs.forEach(x=>x.classList.remove('active'));b.classList.add('active');
const fv=b.dataset.filter;rs.forEach(tr=>{tr.style.display=(fv==='all'||tr.dataset.status===fv)?'':'none'})}));
document.querySelectorAll('[data-action]').forEach(b=>b.addEventListener('click',async()=>{
const a=b.dataset.action;if(a==='cancel'&&!confirm('Cancelar todas as pendentes?'))return;
await fetch(`/api/campaigns/${cid}/${a}`,{method:'POST'});setTimeout(()=>location.reload(),400)}))})();
