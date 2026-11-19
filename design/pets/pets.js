const INK='#2b2b3a', BLUSH='#ff8a8a';
const SP={
 cat:{name:'Кот',fur:'#f5a04a',light:'#ffd9a0',belly:'#fff3e0',line:'#d9853a',stripe:'#e8913f',inner:'#ffb3b3',ears:'cat',tail:'cat',face:'cat'},
 dog:{name:'Собака',fur:'#d39a62',light:'#f1d3a8',belly:'#fff4e4',line:'#a8703f',dark:'#8a5a35',ears:'flop',tail:'stub',face:'dog'},
 chick:{name:'Цыплёнок',fur:'#ffd23f',light:'#fff3a6',belly:'#fff8d0',line:'#e0a800',ears:'tuft',tail:'none',face:'beak',wings:true,beak:'#ff9a3c'},
 bunny:{name:'Кролик',fur:'#ece6e0',light:'#ffffff',belly:'#ffffff',line:'#b9aea3',inner:'#ffc2cc',ears:'bunny',tail:'pom',face:'bunny'},
 turtle:{name:'Черепаха',fur:'#9ad36f',light:'#d4f5b4',belly:'#f3f7c9',line:'#5e9c3e',ears:'none',tail:'none',face:'plain',shell:true},
 fox:{name:'Лиса',fur:'#f27b2f',light:'#ffb47a',belly:'#fffaf3',line:'#c2551a',inner:'#5a3220',ears:'fox',tail:'fox',face:'fox'},
 panda:{name:'Панда',fur:'#f6f6f4',light:'#ffffff',belly:'#ffffff',line:'#a9a9a9',dark:'#2f3138',ears:'round',tail:'none',face:'panda'},
 owl:{name:'Сова',fur:'#a8794e',light:'#d8b48a',belly:'#f1e0c6',line:'#7a5230',ears:'owl',tail:'none',face:'owl',wings:true,beak:'#f2b33d'},
 dragon:{name:'Дракон',fur:'#4fbf8f',light:'#a8ecc8',belly:'#fbe9a6',line:'#2f8a63',ears:'horns',tail:'dragon',face:'plain',wingsBack:'#3aa67a',spikes:true},
 unicorn:{name:'Единорог',fur:'#fbf7ff',light:'#ffffff',belly:'#ffffff',line:'#cdbbe0',inner:'#ffd0e4',ears:'horse',tail:'none',face:'plain',horn:true,mane:true},
 phoenix:{name:'Феникс',fur:'#ff6b3d',light:'#ffc06a',belly:'#ffe0a3',line:'#d94a1e',ears:'flame',tail:'phoenix',face:'beak',wings:true,beak:'#ffd34d'},
};
function tailPoly(pts,w0,w1,fill,line){const [p0,p1,p2,p3]=pts;const N=24,L=[],R=[];for(let i=0;i<=N;i++){const t=i/N,m=1-t;const x=m**3*p0[0]+3*m*m*t*p1[0]+3*m*t*t*p2[0]+t**3*p3[0],y=m**3*p0[1]+3*m*m*t*p1[1]+3*m*t*t*p2[1]+t**3*p3[1];const dx=3*m*m*(p1[0]-p0[0])+6*m*t*(p2[0]-p1[0])+3*t*t*(p3[0]-p2[0]),dy=3*m*m*(p1[1]-p0[1])+6*m*t*(p2[1]-p1[1])+3*t*t*(p3[1]-p2[1]);const n=Math.hypot(dx,dy),w=w0+(w1-w0)*t;L.push([x-dy/n*w,y+dx/n*w]);R.push([x+dy/n*w,y-dx/n*w]);}
 const f=p=>p.map(v=>v.toFixed(1)).join(' ');const e=R[N];return `<path d="M${L.map(f).join(' L')} A${w1} ${w1} 0 0 0 ${f(e)} L${R.reverse().map(f).join(' L')}Z" fill="${fill}" stroke="${line}" stroke-width="2.5" stroke-linejoin="round"/>`;}
function pet(k,stage,emo,uid){
 const S=SP[k], s=[0.72,0.84,0.94,1][stage], id=`${k}${stage}${emo}${uid||''}`;
 const headY=stage>=2?92:112, hr=stage>=2?58:66;
 const R=(x,y)=>`${(100+x*hr).toFixed(1)} ${(headY+y*hr).toFixed(1)}`;
 const g=`url(#u${id})`;
 let o=`<svg width="200" height="210" viewBox="0 -22 200 210"><defs><radialGradient id="u${id}" gradientUnits="userSpaceOnUse" cx="86" cy="${headY-hr*0.45}" r="${hr*1.5}"><stop offset="0" stop-color="${S.light}"/><stop offset="0.75" stop-color="${S.fur}"/></radialGradient></defs>`;
 if(stage==3) o+=`<g fill="#ffe27a"><path d="M30 60 l4 10 l10 4 l-10 4 l-4 10 l-4 -10 l-10 -4 l10 -4z"/><path d="M170 66 l3 7 l7 3 l-7 3 l-3 7 l-3 -7 l-7 -3 l7 -3z"/></g>`;
 o+=`<ellipse cx="100" cy="184" rx="${56*s}" ry="7" fill="#000" opacity=".18"/><g class="J"><g class="Br"><g transform="translate(100 184) scale(${s}) translate(-100 -184)">`;
 const ln=`stroke="${S.line}" stroke-width="2.5" stroke-linejoin="round"`;
 // back layer: tails, shell, back wings
 let back='';
 if(stage>=1){
  if(S.tail=='cat') back+=tailPoly([[130,166],[176,178],[194,140],[170,128]],9.5,5,S.fur,S.line);
  if(S.tail=='fox') back+=tailPoly([[128,166],[186,176],[196,120],[168,104]],13,9,S.fur,S.line)+`<circle cx="168" cy="106" r="10" fill="#fffaf3" stroke="${S.line}" stroke-width="2.5"/>`;
  if(S.tail=='dragon') back+=tailPoly([[128,168],[178,180],[192,150],[186,128]],11,4,S.fur,S.line)+`<path d="M180 128 l10 -8 l2 12z" fill="${S.belly}" stroke="${S.line}" stroke-width="2" stroke-linejoin="round"/>`;
  if(S.tail=='stub') back+=`<g class="tail">`+tailPoly([[136,160],[156,156],[162,140],[160,128]],8,6,S.fur,S.line)+`</g>`;
  if(S.tail=='pom') back+=`<circle cx="152" cy="160" r="13" fill="#fff" stroke="${S.line}" stroke-width="2.5"/>`;
  if(S.tail=='phoenix') back+=`<g stroke="${S.line}" stroke-width="2" stroke-linejoin="round"><path d="M130 160 C160 170 186 160 194 132 C180 146 166 150 150 148Z" fill="#ffb03a"/><path d="M128 166 C162 184 190 176 198 156 C182 166 164 166 148 158Z" fill="#ff6b3d"/></g>`;
 }
 if(S.tail=='cat'||S.tail=='fox'||S.tail=='dragon') back=`<g class="tail">${back}</g>`;
 if(S.shell){const sy=stage>=2?138:140,rx=stage>=2?72:78,ry=stage>=2?50:50; back+=`<ellipse cx="100" cy="${sy}" rx="${rx}" ry="${ry}" fill="#c98b4a" stroke="#8a5a2b" stroke-width="2.5"/><ellipse cx="100" cy="${sy}" rx="${rx-9}" ry="${ry-9}" fill="none" stroke="#e3ad6e" stroke-width="5"/><g fill="#e3ad6e" stroke="#8a5a2b" stroke-width="1.5" stroke-linejoin="round"><path d="M${100-rx+12} ${sy-4} l10 -16 l14 4 l2 18 l-12 10 l-12 -6z"/><path d="M${100+rx-12} ${sy-4} l-10 -16 l-14 4 l-2 18 l12 10 l12 -6z"/></g>`;}
 if(S.wingsBack && stage>=1) back+=`<g stroke="${S.line}" stroke-width="2.5" stroke-linejoin="round" fill="${S.wingsBack}"><path d="M52 ${headY+40} C20 ${headY+20} 18 ${headY-10} 30 ${headY-24} C34 ${headY} 44 ${headY+12} 60 ${headY+18}Z"/><path d="M148 ${headY+40} C180 ${headY+20} 182 ${headY-10} 170 ${headY-24} C166 ${headY} 156 ${headY+12} 140 ${headY+18}Z"/></g>`;
 o+=back;
 if(stage>=2) o+=`<ellipse cx="100" cy="150" rx="54" ry="36" fill="${S.shell?S.belly:g}" ${ln}/><ellipse cx="100" cy="156" rx="30" ry="22" fill="${S.belly}" opacity=".95"/>`;
 // ears behind head
 let ears='', front='';
 const E=S.ears;
 if(E=='flop'){} 
 if(E=='round') ears+=`<circle cx="${100-hr*0.72}" cy="${headY-hr*0.74}" r="${hr*0.3}" fill="${S.dark}"/><circle cx="${100+hr*0.72}" cy="${headY-hr*0.74}" r="${hr*0.3}" fill="${S.dark}"/>`;
 if(E=='bunny') ears+=[-1,1].map(sx=>`<g transform="rotate(${sx*10} ${100+sx*hr*0.38} ${headY-hr*0.8})"><ellipse cx="${100+sx*hr*0.38}" cy="${headY-hr*1.35}" rx="${hr*0.2}" ry="${hr*0.62}" fill="${S.fur}" ${ln}/><ellipse cx="${100+sx*hr*0.38}" cy="${headY-hr*1.3}" rx="${hr*0.1}" ry="${hr*0.46}" fill="${S.inner}"/></g>`).join('');
 if(E=='fox'||E=='horse') ears+=[-1,1].map(sx=>{const b1=R(sx*0.82,-0.42),tip=R(sx*0.72,E=='fox'?-1.45:-1.25),b2=R(sx*0.22,-0.92);return `<path d="M${b1} Q${R(sx*0.9,-1.1)} ${tip} Q${R(sx*0.5,-1.15)} ${b2}Z" fill="${S.fur}" ${ln}/><path d="M${R(sx*0.72,-0.72)} Q${R(sx*0.76,-1.1)} ${R(sx*0.71,-1.3)} Q${R(sx*0.52,-1.05)} ${R(sx*0.42,-0.9)}Z" fill="${S.inner}"/>`}).join('');
 if(E=='owl') ears+=[-1,1].map(sx=>`<path d="M${R(sx*0.75,-0.6)} L${R(sx*0.82,-1.18)} L${R(sx*0.35,-0.92)}Z" fill="${S.fur}" ${ln}/>`).join('');
 if(E=='horns') ears+=[-1,1].map(sx=>`<path d="M${R(sx*0.5,-0.82)} Q${R(sx*0.62,-1.3)} ${R(sx*0.78,-1.36)} Q${R(sx*0.6,-1.0)} ${R(sx*0.28,-0.92)}Z" fill="#fff4d6" ${ln}/>`).join('');
 if(E=='flame'&&stage<3) ears+=`<g stroke="${S.line}" stroke-width="2" stroke-linejoin="round"><path d="M${R(-0.25,-0.9)} C${R(-0.5,-1.3)} ${R(-0.2,-1.4)} ${R(-0.3,-1.6)} C${R(0,-1.4)} ${R(0.05,-1.2)} ${R(0,-0.95)}Z" fill="#ffb03a"/><path d="M${R(-0.08,-0.95)} C${R(-0.15,-1.4)} ${R(0.2,-1.5)} ${R(0.12,-1.75)} C${R(0.42,-1.45)} ${R(0.35,-1.2)} ${R(0.22,-0.92)}Z" fill="#ffd34d"/><path d="M${R(0.15,-0.94)} C${R(0.3,-1.3)} ${R(0.55,-1.3)} ${R(0.5,-1.5)} C${R(0.7,-1.2)} ${R(0.55,-1.0)} ${R(0.4,-0.85)}Z" fill="#ff8a3d"/></g>`;
 if(E=='tuft') ears+=`<path d="M${R(-0.05,-0.96)} C${R(-0.2,-1.3)} ${R(0.05,-1.32)} ${R(0,-1.18)} C${R(0.12,-1.36)} ${R(0.3,-1.2)} ${R(0.1,-0.96)}Z" fill="${S.fur}" ${ln}/>`;
 o+=ears;
 // head
 if(E=='cat'){const P=(deg)=>{const t=deg*Math.PI/180;return `${(100+hr*Math.cos(t)).toFixed(1)} ${(headY-hr*Math.sin(t)).toFixed(1)}`};
  o+=`<path d="M${P(150)} C${R(-0.93,-0.78)} ${R(-0.85,-1.22)} ${R(-0.77,-1.35)} C${R(-0.72,-1.38)} ${R(-0.66,-1.32)} ${R(-0.56,-1.17)} C${R(-0.46,-1.06)} ${R(-0.4,-0.97)} ${P(108)} A${hr} ${hr} 0 0 1 ${P(72)} C${R(0.4,-0.97)} ${R(0.46,-1.06)} ${R(0.56,-1.17)} C${R(0.66,-1.32)} ${R(0.72,-1.38)} ${R(0.77,-1.35)} C${R(0.85,-1.22)} ${R(0.93,-0.78)} ${P(30)} A${hr} ${hr} 0 1 1 ${P(150)} Z" fill="${g}" ${ln}/>`+[-1,1].map(sx=>`<path d="M${R(sx*0.72,-0.86)} C${R(sx*0.72,-1.04)} ${R(sx*0.72,-1.18)} ${R(sx*0.7,-1.2)} C${R(sx*0.64,-1.2)} ${R(sx*0.56,-1.08)} ${R(sx*0.46,-0.98)} Z" fill="${S.inner}"/>`).join('')+`<g stroke="${S.stripe}" stroke-width="4.5" stroke-linecap="round"><path d="M${R(-0.13,-0.94)} L${R(-0.1,-0.78)}"/><path d="M${R(0,-0.98)} L${R(0,-0.8)}"/><path d="M${R(0.13,-0.94)} L${R(0.1,-0.78)}"/></g>`;}
 else o+=`<ellipse cx="100" cy="${headY}" rx="${hr+2}" ry="${hr}" fill="${g}" ${ln}/>`;
 // head decorations
 if(S.face=='fox') o+=`<path d="M${R(-1.0,0.05)} Q${R(-0.5,-0.1)} ${R(0,0.2)} Q${R(0.5,-0.1)} ${R(1.0,0.05)} Q${R(0.8,0.75)} ${R(0,0.98)} Q${R(-0.8,0.75)} ${R(-1.0,0.05)}Z" fill="#fffaf3"/>`;
 if(S.face=='panda') o+=[-1,1].map(sx=>`<ellipse cx="${100+sx*24}" cy="${headY-6}" rx="13" ry="17" transform="rotate(${sx*-25} ${100+sx*24} ${headY-6})" fill="${S.dark}"/>`).join('');
 if(S.face=='owl') o+=[-1,1].map(sx=>`<circle cx="${100+sx*24}" cy="${headY-8}" r="20" fill="${S.belly}" stroke="${S.line}" stroke-width="1.5"/>`).join('');
 if(S.mane) o+=`<path d="M${R(-0.1,-1.0)} C${R(-0.7,-1.05)} ${R(-1.1,-0.5)} ${R(-0.95,0.15)} C${R(-0.8,-0.3)} ${R(-0.6,-0.6)} ${R(-0.2,-0.72)}Z" fill="#f7a8d8"/><path d="M${R(-0.15,-0.98)} C${R(-0.6,-0.9)} ${R(-0.85,-0.5)} ${R(-0.82,-0.05)} C${R(-0.65,-0.4)} ${R(-0.45,-0.6)} ${R(-0.1,-0.76)}Z" fill="#b7a4f7"/><path d="M${R(0.05,-1.0)} C${R(0.4,-1.02)} ${R(0.55,-0.9)} ${R(0.62,-0.78)} C${R(0.4,-0.82)} ${R(0.2,-0.8)} ${R(0.0,-0.74)}Z" fill="#9fd8f7"/>`;
 const hornSvg=S.horn?`<path d="M${R(-0.13,-0.92)} L${R(0,-1.5)} L${R(0.13,-0.92)}Z" fill="#ffd34d" stroke="#d9a400" stroke-width="2" stroke-linejoin="round"/><path d="M${R(-0.1,-1.08)} L${R(0.08,-1.02)} M${R(-0.07,-1.22)} L${R(0.06,-1.17)} M${R(-0.04,-1.36)} L${R(0.04,-1.32)}" stroke="#d9a400" stroke-width="1.5"/>`:'';
 if(stage<3) o+=hornSvg;
 if(E=='flop') o+=[-1,1].map(sx=>`<path d="M${R(sx*0.55,-0.88)} C${R(sx*1.05,-0.95)} ${R(sx*1.15,-0.2)} ${R(sx*0.95,0.15)} C${R(sx*0.8,0.3)} ${R(sx*0.68,0.0)} ${R(sx*0.72,-0.35)} C${R(sx*0.74,-0.6)} ${R(sx*0.62,-0.75)} ${R(sx*0.4,-0.82)}Z" fill="${S.dark}" stroke="${S.line}" stroke-width="2" stroke-linejoin="round"/>`).join('');
 // muzzle
 const y=headY-8, beak=S.face=='beak'||S.face=='owl';
 if(!beak && S.face!='fox' && S.face!='panda') o+=`<ellipse cx="100" cy="${headY+(stage<2?24:20)}" rx="${stage<2?34:30}" ry="${stage<2?24:20}" fill="${S.belly}" opacity=".95"/>`;
 if(S.face=='panda') o+=`<ellipse cx="100" cy="${headY+22}" rx="26" ry="18" fill="#fff"/>`;
 // eyes
 if(emo==2) o+=`<path d="M66 ${y} q10 8 20 0 M114 ${y} q10 8 20 0" stroke="${S.face=='panda'?'#fff':INK}" stroke-width="3.5" fill="none" stroke-linecap="round"/>`;
 else if(emo==3) o+=`<path d="M66 ${y+3} q10 -12 20 0 M114 ${y+3} q10 -12 20 0" stroke="${S.face=='panda'?'#fff':INK}" stroke-width="4" fill="none" stroke-linecap="round"/>`;
 else {const ry=stage==0?13:11.5; o+=`<g class="eyes"><ellipse cx="76" cy="${y}" rx="${ry-2}" ry="${ry}" fill="${INK}"/><ellipse cx="124" cy="${y}" rx="${ry-2}" ry="${ry}" fill="${INK}"/><circle cx="79" cy="${y-4}" r="3.8" fill="#fff"/><circle cx="127" cy="${y-4}" r="3.8" fill="#fff"/><circle cx="73.5" cy="${y+4}" r="1.8" fill="#fff" opacity=".8"/><circle cx="121.5" cy="${y+4}" r="1.8" fill="#fff" opacity=".8"/></g>`;
  if(emo==1) o+=`<path d="M64 ${y-15} L86 ${y-22} M136 ${y-15} L114 ${y-22}" stroke="${S.face=='panda'?'#fff':INK}" stroke-width="3" stroke-linecap="round"/><path d="M70 ${y+12} q-4 8 0 12 q4 -4 0 -12z" fill="#7cc4ff"/>`;}
 o+=`<ellipse cx="60" cy="${y+20}" rx="10" ry="6" fill="${BLUSH}" opacity="${emo==1?.25:.5}"/><ellipse cx="140" cy="${y+20}" rx="10" ry="6" fill="${BLUSH}" opacity="${emo==1?.25:.5}"/>`;
 // nose/mouth
 if(beak){o+=`<path d="M92 ${y+12} Q100 ${y+8} 108 ${y+12} L100 ${y+24}Z" fill="${S.beak}" stroke="#d98a1e" stroke-width="1.5" stroke-linejoin="round"/>`; if(emo==3) o+=`<path d="M94 ${y+17} L106 ${y+17} L100 ${y+28}Z" fill="#e0602a"/>`;}
 else {
  const nose = S.face=='dog'||S.face=='panda'? `<ellipse cx="100" cy="${y+14}" rx="7" ry="5" fill="${INK}"/>` : (S.face=='fox'?`<ellipse cx="100" cy="${y+14}" rx="5" ry="4" fill="${INK}"/>`:`<path d="M96 ${y+14} h8 l-4 4 z" fill="#d9605a"/>`);
  o+=nose;
  if(emo==0) o+=`<path d="M92 ${y+23} q4 5 8 0 q4 5 8 0" stroke="${INK}" stroke-width="2.5" fill="none" stroke-linecap="round"/>`;
  if(emo==1) o+=`<path d="M93 ${y+28} q7 -6 14 0" stroke="${INK}" stroke-width="2.5" fill="none" stroke-linecap="round"/>`;
  if(emo==2) o+=`<ellipse cx="100" cy="${y+26}" rx="3" ry="2.5" fill="${INK}"/>`;
  if(emo==3) o+=`<path d="M90 ${y+21} q10 14 20 0 z" fill="#c9504a"/>`;
  if(S.face=='dog'&&(emo==0||emo==3)) o+=`<path d="M96 ${y+27} q4 9 8 0z" fill="#ff7d8a"/>`;
  if(S.face=='bunny') o+=`<rect x="96" y="${y+25}" width="8" height="7" rx="1.5" fill="#fff" stroke="${S.line}" stroke-width="1"/>`;
  if(S.face=='cat') o+=`<g stroke="${S.line}" stroke-width="1.6" stroke-linecap="round" opacity=".7"><path d="M${R(-0.62,0.22)} L${R(-0.98,0.14)}"/><path d="M${R(-0.62,0.3)} L${R(-0.96,0.34)}"/><path d="M${R(0.62,0.22)} L${R(0.98,0.14)}"/><path d="M${R(0.62,0.3)} L${R(0.96,0.34)}"/></g>`;
 }
 // wings at sides
 if(S.wings) o+=[-1,1].map(sx=>`<path d="M${100+sx*(stage>=2?50:58)} ${stage>=2?140:118} C${100+sx*74} ${stage>=2?146:126} ${100+sx*76} ${stage>=2?166:150} ${100+sx*60} ${stage>=2?172:160} C${100+sx*56} ${stage>=2?160:146} ${100+sx*50} ${stage>=2?150:132} ${100+sx*(stage>=2?50:58)} ${stage>=2?140:118}Z" fill="${S.fur}" ${ln}/>`).join('');
 if(S.face=='owl'&&stage>=2) o+=`<g stroke="${S.line}" stroke-width="2" fill="none" stroke-linecap="round"><path d="M90 150 l5 5 l5 -5 l5 5 l5 -5"/><path d="M90 162 l5 5 l5 -5 l5 5 l5 -5"/></g>`;
 if(S.spikes&&stage>=1) o+=`<g fill="${S.belly}" stroke="${S.line}" stroke-width="2" stroke-linejoin="round"><path d="M${R(-0.08,-0.98)} l8 -14 l8 14z"/></g>`;
 // paws
 const pawC = S.face=='panda'? S.dark : (S.face=='beak'||S.face=='owl' ? (S.beak) : S.light);
 if(S.face=='beak'||S.face=='owl') o+=`<g fill="${pawC}"><path d="M70 176 l-6 6 h24 l-6 -6z"/><path d="M118 176 l-6 6 h24 l-6 -6z"/></g>`;
 else if(S.horn) o+=[78,122].map(x=>`<path d="M${x-12} 166 L${x-13} 178 Q${x} 183 ${x+13} 178 L${x+12} 166Z" fill="#fbf7ff" stroke="${S.line}" stroke-width="2.5" stroke-linejoin="round"/><path d="M${x-13} 174 Q${x} 179 ${x+13} 174 L${x+13} 178 Q${x} 183 ${x-13} 178Z" fill="#c9a8ef" stroke="#a989d6" stroke-width="2" stroke-linejoin="round"/>`).join('');
 else o+=`<ellipse cx="78" cy="176" rx="14" ry="8" fill="${pawC}"/><ellipse cx="122" cy="176" rx="14" ry="8" fill="${pawC}"/>`;
 if(S.face=='panda'&&stage>=2) o+=`<ellipse cx="54" cy="148" rx="12" ry="20" fill="${S.dark}"/><ellipse cx="146" cy="148" rx="12" ry="20" fill="${S.dark}"/>`;
 // stage extras
 if(stage==2 && !S.wings && !S.shell){const ny=headY+hr*0.86,w=hr*0.66;o+=`<path d="M${100-w} ${ny-8} Q100 ${ny+14} ${100+w} ${ny-8}" stroke="#e8505b" stroke-width="8" fill="none" stroke-linecap="round"/><circle cx="100" cy="${ny+9}" r="7" fill="#ffd34d" stroke="#d9a400" stroke-width="1.5"/><path d="M95 ${ny+10} h10" stroke="#b07f00" stroke-width="1.5" stroke-linecap="round"/><circle cx="100" cy="${ny+13}" r="1.6" fill="#8a6200"/>`;}
 if(stage==3){const by=headY-hr+10;o+=`<path d="M78 ${by} L74 ${by-24} L88 ${by-12} L100 ${by-30} L112 ${by-12} L126 ${by-24} L122 ${by} Q100 ${by+8} 78 ${by} Z" fill="#ffd34d" stroke="#e0a400" stroke-width="2.5" stroke-linejoin="round"/><path d="M80 ${by-3} Q100 ${by+4} 120 ${by-3}" stroke="#e0a400" stroke-width="2" fill="none"/><circle cx="100" cy="${by-11}" r="3.5" fill="#ff6b8a"/><circle cx="74" cy="${by-25}" r="2.5" fill="#ffd34d"/><circle cx="100" cy="${by-31}" r="2.8" fill="#ffd34d"/><circle cx="126" cy="${by-25}" r="2.5" fill="#ffd34d"/>`;}
 if(stage==3) o+=hornSvg;
 o+=`</g></g></g>`;
 if(emo==2) o+=`<text class="z" x="150" y="44" font-size="22" font-weight="700" fill="#cfd8ff">z</text><text class="z z2" x="166" y="28" font-size="16" font-weight="700" fill="#cfd8ff">z</text>`;
 return o+'</svg>';
}
