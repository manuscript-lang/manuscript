const fs=require('fs');const b=fs.readFileSync(process.argv[2]);
const pe=b.readUInt32LE(0x3c);const nsec=b.readUInt16LE(pe+6);const opt=pe+24;const osz=b.readUInt16LE(pe+20);
const imgBase=Number(b.readBigUInt64LE(opt+24));const soi=b.readUInt32LE(opt+56);const sa=b.readUInt32LE(opt+32);
const dd=opt+112;const dir=i=>[b.readUInt32LE(dd+i*8),b.readUInt32LE(dd+i*8+4)];
const secs=[];for(let i=0;i<nsec;i++){const s=opt+osz+i*40;secs.push({n:b.toString('latin1',s,s+8).replace(/\0+$/,''),vs:b.readUInt32LE(s+8),va:b.readUInt32LE(s+12),rs:b.readUInt32LE(s+16),rp:b.readUInt32LE(s+20)});}
const sec=r=>secs.find(s=>r>=s.va&&r<s.va+Math.max(s.vs,s.rs));
const off=r=>{const s=sec(r);return s?s.rp+r-s.va:-1};
let bad=[];const note=m=>{if(bad.length<25)bad.push(m)};
console.log('SizeOfImage',soi.toString(16),'secs',secs.map(s=>s.n+':'+s.va.toString(16)+'+'+s.vs.toString(16)).join(' '));
const [pr,ps]=dir(3);let prev=-1,n=ps/8;
for(let i=0;i<n;i++){const o=off(pr)+i*8;const bg=b.readUInt32LE(o),ux=b.readUInt32LE(o+4);
 if(bg<prev)note('unsorted pdata '+i+' '+bg.toString(16)+'<'+prev.toString(16));
 if(bg===prev)note('dup pdata '+i);prev=bg;
 const s=sec(bg);if(!s||s.n!=='.text')note('pdata begin outside .text '+bg.toString(16));
 if((ux&3)===0){const x=sec(ux);if(!x)note('xdata rva outside image '+ux.toString(16));}}
const [rr,rs]=dir(5);let p=0;const ro=off(rr);while(p<rs){const page=b.readUInt32LE(ro+p),sz=b.readUInt32LE(ro+p+4);
 if(sz<8||sz%4)note('bad reloc block '+page.toString(16)+' '+sz);
 for(let q=8;q<sz;q+=2){const e=b.readUInt16LE(ro+p+q);const t=e>>12,a=page+(e&0xfff);if(t===0)continue;if(t!==10)note('reloc type '+t);if(a%8)note('misaligned reloc '+a.toString(16));if(a+8>soi)note('reloc beyond image');else{const ss=sec(a);if(!ss)note('reloc in no section '+a.toString(16));}}
 p+=sz;}
const [tr,ts]=dir(9);if(ts){const o=off(tr);const s0=Number(b.readBigUInt64LE(o)),e0=Number(b.readBigUInt64LE(o+8)),idx=Number(b.readBigUInt64LE(o+16)),cb=Number(b.readBigUInt64LE(o+24));
 console.log('TLS',s0.toString(16),e0.toString(16),idx.toString(16),cb.toString(16),'size',e0-s0);}
const [ir,is]=dir(1);console.log('imports',ir.toString(16),is);

// unwind validation
{let prevEnd=0;let pk=0,xd=0;for(let i=0;i<n;i++){const o=off(pr)+i*8;const bg=b.readUInt32LE(o),ux=b.readUInt32LE(o+4);let len;
 if(ux&3){pk++;len=((ux>>2)&0x7ff)*4;if(len===0)note('packed zero length '+i);}
 else{xd++;const xo=off(ux);if(xo<0){note('xdata unmapped '+i);continue;}let w=b.readUInt32LE(xo);len=(w&0x3ffff)*4;let hdr=4;let cw=(w>>27)&31,ec=(w>>22)&31;const ex=(w>>20)&1;
  if(cw===0&&ec===0){const w2=b.readUInt32LE(xo+4);cw=(w2>>16)&255;ec=w2&0xffff;hdr=8;}
  if(((w>>21)&1)===0&&ec>0&&0){}
  const ver=(w>>18)&3;if(ver!==0)note('xdata version '+ver+' at '+i);
  const total=hdr+(((w>>21)&1)?0:ec*4)+cw*4;if(total>0x10000)note('huge xdata '+i);}
 if(bg<prevEnd)note('pdata overlap '+i+' '+bg.toString(16)+'<'+prevEnd.toString(16));prevEnd=bg+len;
 const ts=secs.find(x=>x.n==='.text');if(bg+len>ts.va+ts.vs)note('function past .text '+i);}
 console.log('packed',pk,'xdata',xd);}
console.log('pdata entries',n,'problems',bad.length);bad.forEach(x=>console.log(' BAD',x));
