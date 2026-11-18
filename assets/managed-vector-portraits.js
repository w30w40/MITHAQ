/* MITHAQ managed-profile vector portraits: deterministic local illustrations, no external assets. */
(function(){
 'use strict';
 const palettes=[['#f7dfe5','#b84f68','#f0c49d'],['#e2edf8','#345f89','#c88e69'],['#f4ead8','#8b6b4c','#d9a77e'],['#e6e5f6','#665d9c','#a96f50'],['#dff0e8','#477d69','#e0b58f'],['#f8e7d4','#a76a3d','#bd8664'],['#e5eef0','#527b82','#e5bd9b'],['#f1e3ef','#956b8e','#9b654d']];
 const hash=v=>{let h=2166136261;for(const c of String(v||'')){h^=c.charCodeAt(0);h=Math.imul(h,16777619);}return h>>>0;};
 function portrait(id,gender){
  const h=hash(id),p=palettes[h%palettes.length],female=/أنثى|انثى|امرأة|female|wife/i.test(String(gender||'')),bg=p[0],cloth=female?'#222b39':'#f2f1e9',skin=p[2],accent=p[1],x=46+(h%5),y=48+(h%3);
  let head;
  if(female) head='<path d="M17 91 Q17 53 25 32 Q32 8 49 8 Q73 8 79 34 Q87 60 82 91 L72 91 Q69 63 49 62 Q29 64 27 91Z" fill="'+cloth+'"/><path d="M25 38 Q27 9 49 9 Q75 8 78 39 Q69 29 61 29 Q46 41 25 38Z" fill="'+accent+'"/><path d="M29 42 Q30 24 49 23 Q68 23 72 43 L72 61 Q69 75 49 76 Q31 73 29 58Z" fill="'+skin+'"/><path d="M22 92 Q24 64 36 59 Q48 69 62 59 Q75 64 78 92Z" fill="'+cloth+'"/>';
  else head='<path d="M29 40 Q28 17 48 17 Q70 17 70 41 L68 63 Q64 75 49 75 Q34 74 30 61Z" fill="'+skin+'"/><path d="M24 30 Q25 8 49 8 Q73 8 75 31 L70 37 Q60 24 49 25 Q37 24 28 38Z" fill="'+accent+'"/><path d="M19 29 Q49 14 80 29 L75 38 Q48 30 24 39Z" fill="#fff" stroke="'+accent+'" stroke-width="2"/><path d="M24 34 L31 40 M36 31 L42 38 M50 30 L55 37 M65 32 L70 39" stroke="'+accent+'" stroke-width="2"/><path d="M18 92 Q22 67 36 61 Q49 70 62 61 Q76 67 80 92Z" fill="'+cloth+'"/>';
  return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 96 96" role="img" aria-label="'+(female?'رسم توضيحي لامرأة بزي محتشم':'رسم توضيحي لرجل بالثوب والشماغ')+'"><rect width="96" height="96" rx="48" fill="'+bg+'"/><circle cx="48" cy="46" r="37" fill="#fff" opacity=".24"/>'+head+'<path d="M'+(x-7)+' '+y+'h3 M'+(x+7)+' '+y+'h3" stroke="#493a35" stroke-width="2.2" stroke-linecap="round"/><path d="M44 57 Q49 60 54 57" fill="none" stroke="#8b5148" stroke-width="1.8" stroke-linecap="round"/></svg>';
 }
 function apply(node,id,gender){if(!node)return;node.classList.add('mithaq-managed-vector-avatar');node.innerHTML=portrait(id,gender);node.setAttribute('aria-label','رسم رمزي لحساب افتراضي');}
 const css=document.createElement('style');css.textContent='.mithaq-managed-vector-avatar{overflow:hidden!important;padding:0!important;background:#f7e9ed!important;display:flex!important;align-items:center!important;justify-content:center!important}.mithaq-managed-vector-avatar svg{display:block;width:100%;height:100%}.mithaq-full-member-profile-avatar.mithaq-managed-vector-avatar{width:88px;height:88px;border-radius:50%;flex:none}';document.head.appendChild(css);
 const oldDecorate=window.decorateMithaqMemberAvatar;
 if(typeof oldDecorate==='function')window.decorateMithaqMemberAvatar=function(node,id){const person=typeof mithaqMemberCache!=='undefined'&&Array.isArray(mithaqMemberCache)?mithaqMemberCache.find(x=>String(x.id)===String(id)&&x.is_platform_managed===true):null;if(person){apply(node,id,person.details&&person.details.gender);return;}oldDecorate.apply(this,arguments);};
 const oldProfile=window.showManagedMemberProfile;
 if(typeof oldProfile==='function')window.showManagedMemberProfile=function(person){oldProfile.apply(this,arguments);apply(document.querySelector('#mithaqFullMemberProfile .mithaq-full-member-profile-avatar'),person.id,person.details&&person.details.gender);};

 // Managed profiles: make safe, clearly disclosed interactions clickable.
 const interestKey='mithaq-managed-profile-interests-v1';
 function readInterests(){try{return JSON.parse(localStorage.getItem(interestKey)||'[]')}catch(_){return []}}
 function writeInterests(ids){try{localStorage.setItem(interestKey,JSON.stringify(ids))}catch(_){}}
 function isInterested(id){return readInterests().includes(String(id))}
 function toggleInterest(id,button){
  const ids=readInterests(),key=String(id),next=ids.includes(key)?ids.filter(x=>x!==key):ids.concat(key);
  writeInterests(next);if(button){button.textContent=next.includes(key)?'✓ ضمن الاهتمامات':'＋ إضافة للاهتمام';button.setAttribute('aria-pressed',next.includes(key)?'true':'false');}
 }
 function interestButton(id){
  const b=document.createElement('button');b.type='button';b.className='mithaq-managed-interest-button';
  b.textContent=isInterested(id)?'✓ ضمن الاهتمامات':'＋ إضافة للاهتمام';b.setAttribute('aria-pressed',isInterested(id)?'true':'false');
  b.addEventListener('click',()=>toggleInterest(id,b));return b;
 }
 const actionCss=document.createElement('style');
 actionCss.textContent='.mithaq-managed-actions{display:flex;gap:9px;flex-wrap:wrap;margin:14px 0}.mithaq-managed-actions button,.mithaq-managed-interest-button{min-height:42px;border-radius:12px;padding:9px 13px;background:#fce8ef;color:#a52c52;border:1px solid #efc6d4;font-weight:700}.mithaq-managed-actions .mithaq-managed-message{background:#f1f4f7;color:#425466;border-color:#dce3ea}.mithaq-managed-note{padding:10px 12px;border-radius:10px;background:#fff8e8;border:1px solid #f0dfb2;color:#75551b;font-size:12px;line-height:1.8;margin-top:8px}';
 document.head.appendChild(actionCss);
 function refreshManagedCards(){
  document.querySelectorAll('#membersGrid .mithaq-directory-card').forEach(card=>{
   const label=card.querySelector('.mithaq-managed-member-label');if(!label)return;
   const personName=card.querySelector('h3')?.textContent||'';
   const person=typeof mithaqMemberCache!=='undefined'&&Array.isArray(mithaqMemberCache)?mithaqMemberCache.find(p=>p.is_platform_managed===true&&String(p.display_name||'')===personName):null;
   if(!person)return;
   const old=card.querySelector('.mithaq-managed-interest-button');if(old)return;
   const oldButton=[...card.querySelectorAll('button')].find(b=>b.disabled||b.textContent.includes('غير متاح'));
   if(oldButton)oldButton.replaceWith(interestButton(person.id));
   else card.append(interestButton(person.id));
  });
 }
 const grid=document.getElementById('membersGrid');
 if(grid&&typeof MutationObserver!=='undefined')new MutationObserver(refreshManagedCards).observe(grid,{childList:true,subtree:true});
 document.addEventListener('click',()=>setTimeout(refreshManagedCards,0),true);
 const previousProfile=window.showManagedMemberProfile;
 if(typeof previousProfile==='function')window.showManagedMemberProfile=function(person){
  previousProfile.apply(this,arguments);
  const page=document.getElementById('mithaqFullMemberProfile');if(!page)return;
  const disclosure=page.querySelector('.mithaq-managed-disclosure');
  if(disclosure)disclosure.textContent='هذا ملف افتراضي تديره منصة ميثاق، وليس حساب شخص حقيقي. يمكنك استعراضه وإضافته إلى اهتماماتك؛ لا يوجد شخص يستقبل الرسائل أو يرد عليها.';
  const content=page.querySelector('.mithaq-full-member-profile-content');
  if(content&&!content.querySelector('.mithaq-managed-actions')){
   const actions=document.createElement('div');actions.className='mithaq-managed-actions';
   actions.append(interestButton(person.id));
   const msg=document.createElement('button');msg.type='button';msg.className='mithaq-managed-message';msg.textContent='✉ إرسال رسالة';
   msg.addEventListener('click',()=>window.alert('هذا حساب افتراضي تحت إدارة ميثاق، ولا يوجد شخص حقيقي يستقبل الرسائل أو يرد عليها. يمكنك إضافة الملف إلى اهتماماتك.'));
   actions.append(msg);
   const note=document.createElement('p');note.className='mithaq-managed-note';note.textContent='التفاعل المتاح: عرض الملف وإضافته أو إزالته من الاهتمامات. زر الرسالة يعرض هذا التنبيه ولا يرسل رسالة لشخص وهمي.';
   content.append(actions,note);
  }
 };
 setTimeout(refreshManagedCards,300);

})();