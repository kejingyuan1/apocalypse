// 末日堡垒 — 精灵表生成器 (末日堡垒 Phase E)
// 用纯 node (zlib) 生成多帧动画 PNG，供 Godot AnimatedSprite2D + SpriteFrames 使用。
// 运行: node tools/gen_sprites.mjs  ->  输出到 assets/sheets/
import { deflateSync } from 'node:zlib';
import { writeFileSync, mkdirSync } from 'node:fs';
import { dirname } from 'node:path';

const FRAME = 64;           // 每帧像素尺寸
const OUT = 'assets/sheets';

// ---------- PNG 编码 ----------
function crc32(buf) {
  let c = ~0;
  for (let i = 0; i < buf.length; i++) {
    c ^= buf[i];
    for (let k = 0; k < 8; k++) c = (c >>> 1) ^ (0xEDB88320 & -(c & 1));
  }
  return (~c) >>> 0;
}
function chunk(type, data) {
  const t = Buffer.from(type, 'ascii');
  const len = Buffer.alloc(4); len.writeUInt32BE(data.length, 0);
  const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(Buffer.concat([t, data])), 0);
  return Buffer.concat([len, t, data, crc]);
}
function encodePNG(w, h, rgba) {
  const sig = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4);
  ihdr[8] = 8; ihdr[9] = 6; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;
  const raw = Buffer.alloc((w * 4 + 1) * h);
  for (let y = 0; y < h; y++) {
    raw[y * (w * 4 + 1)] = 0;
    rgba.copy(raw, y * (w * 4 + 1) + 1, y * w * 4, (y + 1) * w * 4);
  }
  const idat = deflateSync(raw, { level: 9 });
  return Buffer.concat([sig, chunk('IHDR', ihdr), chunk('IDAT', idat), chunk('IEND', Buffer.alloc(0))]);
}

// ---------- 帧缓冲 ----------
class Buf {
  constructor(w, h) { this.w = w; this.h = h; this.d = Buffer.alloc(w * h * 4, 0); }
  set(x, y, c) {
    x = Math.round(x); y = Math.round(y);
    if (x < 0 || y < 0 || x >= this.w || y >= this.h) return;
    const i = (y * this.w + x) * 4;
    const a = c.a === undefined ? 255 : c.a;
    if (a >= 255) { this.d[i]=c.r; this.d[i+1]=c.g; this.d[i+2]=c.b; this.d[i+3]=255; return; }
    if (a <= 0) return;
    const af = a / 255, ia = 1 - af, da = this.d[i+3] / 255;
    const outA = af + ia * da;
    if (outA <= 0) return;
    this.d[i]   = Math.round((c.r*af + this.d[i]*ia*da) / outA);
    this.d[i+1] = Math.round((c.g*af + this.d[i+1]*ia*da) / outA);
    this.d[i+2] = Math.round((c.b*af + this.d[i+2]*ia*da) / outA);
    this.d[i+3] = Math.round(outA * 255);
  }
  rect(x, y, w, h, c) { for (let yy=0; yy<h; yy++) for (let xx=0; xx<w; xx++) this.set(x+xx, y+yy, c); }
  // 圆角矩形
  rrect(x, y, w, h, r, c) {
    for (let yy=0; yy<h; yy++) for (let xx=0; xx<w; xx++) {
      const px=x+xx, py=y+yy;
      if (xx<r && yy<r && (r-xx)**2+(r-yy)**2 > r*r) continue;
      if (xx>=w-r && yy<r && (xx-(w-r+1))**2+(r-yy)**2 > r*r) continue;
      if (xx<r && yy>=h-r && (r-xx)**2+(yy-(h-r+1))**2 > r*r) continue;
      if (xx>=w-r && yy>=h-r && (xx-(w-r+1))**2+(yy-(h-r+1))**2 > r*r) continue;
      this.set(px, py, c);
    }
  }
  circle(cx, cy, r, c) { const r2=r*r; for (let yy=-r; yy<=r; yy++) for (let xx=-r; xx<=r; xx++) if (xx*xx+yy*yy<=r2) this.set(cx+xx, cy+yy, c); }
  ellipse(cx, cy, rx, ry, c) { for (let yy=-ry; yy<=ry; yy++) for (let xx=-rx; xx<=rx; xx++) if (rx>0 && ry>0 && (xx*xx)/(rx*rx)+(yy*yy)/(ry*ry)<=1) this.set(cx+xx, cy+yy, c); }
  line(x0, y0, x1, y1, c, t=1) {
    x0=Math.round(x0); y0=Math.round(y0); x1=Math.round(x1); y1=Math.round(y1);
    const dx=Math.abs(x1-x0), dy=Math.abs(y1-y0), sx=x0<x1?1:-1, sy=y0<y1?1:-1;
    let err=dx-dy, x=x0, y=y0;
    while (true) {
      if (t<=1) this.set(x,y,c); else this.circle(x,y,t/2,c);
      if (x===x1 && y===y1) break;
      const e2=2*err;
      if (e2>-dy){ err-=dy; x+=sx; }
      if (e2<dx){ err+=dx; y+=sy; }
    }
  }
  tri(ax,ay,bx,by,cx,cy,c) {
    const minx=Math.floor(Math.min(ax,bx,cx)), maxx=Math.ceil(Math.max(ax,bx,cx));
    const miny=Math.floor(Math.min(ay,by,cy)), maxy=Math.ceil(Math.max(ay,by,cy));
    for (let y=miny;y<=maxy;y++) for (let x=minx;x<=maxx;x++){
      const d1=(x-ax)*(by-ay)-(y-ay)*(bx-ax);
      const d2=(x-bx)*(cy-by)-(y-by)*(cx-bx);
      const d3=(x-cx)*(ay-cy)-(y-cy)*(ax-cx);
      if ((d1>=0&&d2>=0&&d3>=0)||(d1<=0&&d2<=0&&d3<=0)) this.set(x,y,c);
    }
  }
}
const C = (r,g,b,a=255)=>({r,g,b,a});
const shade = (c,f)=>C(Math.max(0,Math.min(255,c.r*f)),Math.max(0,Math.min(255,c.g*f)),Math.max(0,Math.min(255,c.b*f)),c.a);

// ---------- 实体绘制 ----------
// 丧尸：朝右行走 4 帧循环。f=0..3
function drawZombie(b, f, base, kind) {
  const cx = FRAME/2;
  const p = f/4 * Math.PI*2;
  const bob = Math.sin(p*2) * 1.6;
  const step = Math.sin(p) * 5;          // 腿前后
  const armSwing = Math.sin(p) * 6;
  // 地面阴影
  b.ellipse(cx, 58, 16, 5, C(0,0,0,80));
  // 腿 (两条，交替)
  b.line(cx-5, 44-bob, cx-5+step, 56, shade(base,0.7), 5);
  b.line(cx+5, 44-bob, cx+5-step, 56, shade(base,0.85), 5);
  // 躯干（腐肉，略前倾）
  b.rrect(cx-11, 26-bob, 22, 20, 6, base);
  b.rrect(cx-9, 28-bob, 18, 10, 4, shade(base,1.12)); // 高光带
  // 破洞/暗斑（确定性）
  b.circle(cx-3, 36-bob, 2.2, shade(base,0.6));
  b.circle(cx+5, 32-bob, 1.8, shade(base,0.65));
  // 前伸手臂（丧尸特征：双前臂前伸）
  b.line(cx+6, 30-bob, cx+15, 34-bob+armSwing*0.3, shade(base,0.8), 4);
  b.line(cx+6, 36-bob, cx+15, 40-bob-armSwing*0.3, shade(base,0.8), 4);
  b.circle(cx+15, 34-bob+armSwing*0.3, 2.2, shade(base,0.9));
  b.circle(cx+15, 40-bob-armSwing*0.3, 2.2, shade(base,0.9));
  // 头
  const hy = 16-bob;
  b.circle(cx, hy, 9, base);
  b.circle(cx-2, hy-2, 5, shade(base,1.15)); // 顶光
  // 凹陷眼（黑）+ 红点
  b.circle(cx+3, hy-1, 2.4, C(10,10,12));
  b.circle(cx+3, hy-1, 1.1, C(220,40,40));
  b.circle(cx+7, hy, 2.0, C(10,10,12));
  // 嘴（黑裂）
  b.line(cx+2, hy+4, cx+8, hy+5, C(15,10,12), 2);
  // spitter 额外：背部毒囊
  if (kind === 'spitter') {
    b.circle(cx-8, 30-bob, 4, C(150,60,180));
    b.circle(cx-9, 29-bob, 1.6, C(220,120,255));
  }
  // runner 额外：速度残影线
  if (kind === 'runner') {
    b.line(cx-14, 30-bob, cx-18, 30-bob, C(220,80,70,120), 2);
    b.line(cx-14, 38-bob, cx-19, 38-bob, C(220,80,70,90), 2);
  }
}

// 防御塔：默认炮管朝上（运行时用节点 rotation 瞄准）
function drawTurret(b, fireFrame) {
  const cx = FRAME/2, cy = FRAME/2+4;
  b.ellipse(cx, 56, 17, 5, C(0,0,0,80));
  // 底座
  b.circle(cx, cy, 21, C(70,76,84));
  b.circle(cx, cy, 16, C(110,118,128));
  b.circle(cx, cy, 16, C(110,118,128)); // 环
  b.circle(cx, cy, 12, C(64,70,78));
  // 旋转指示点
  b.circle(cx+10, cy-6, 2.5, C(120,200,255,200));
  // 炮管（朝上即 -y）
  b.rrect(cx-5, cy-30, 10, 22, 3, C(140,148,158));
  b.rrect(cx-5, cy-30, 10, 6, 3, C(180,188,198));
  b.circle(cx, cy-30, 6, C(90,96,104));
  // 开火闪光（fireFrame: 0无 1大 2中 3小）
  if (fireFrame >= 1) {
    const fl = [0, 14, 9, 5][fireFrame] || 0;
    b.circle(cx, cy-32, fl, C(255,230,150,230));
    b.circle(cx, cy-32, fl*0.5, C(255,255,230,255));
    if (fireFrame === 1) { // 曳光起点
      b.line(cx, cy-32, cx, cy-46, C(255,220,120,180), 3);
    }
  }
}

// 核心/指挥：脉动 + 内部旋转
function drawCore(b, f) {
  const cx = FRAME/2, cy = FRAME/2;
  const pulse = 0.5 + 0.5*Math.sin(f/4*Math.PI*2);
  b.ellipse(cx, 58, 18, 5, C(0,0,0,70));
  // 外发光
  b.circle(cx, cy, 26 + pulse*4, C(235,150,60, 40+pulse*30));
  b.circle(cx, cy, 22, C(60,46,38));
  b.rrect(cx-18, cy-18, 36, 36, 8, C(120,84,52));
  b.rrect(cx-15, cy-15, 30, 30, 6, C(170,110,60));
  // 内部旋转核心（六角）
  const spin = f/4*Math.PI*2;
  const pts = [];
  for (let i=0;i<6;i++){ const a=spin+i/6*Math.PI*2; pts.push([cx+Math.cos(a)*10, cy+Math.sin(a)*10]); }
  b.tri(pts[0][0],pts[0][1],pts[1][0],pts[1][1],pts[2][0],pts[2][1], C(255,200,110));
  b.tri(pts[2][0],pts[2][1],pts[3][0],pts[3][1],pts[4][0],pts[4][1], C(255,200,110));
  b.tri(pts[4][0],pts[4][1],pts[5][0],pts[5][1],pts[0][0],pts[0][1], C(255,200,110));
  b.circle(cx, cy, 5+pulse*2, C(255,245,210,255));
}

// 生产房：齿轮旋转 + 烟囱冒烟
function drawProduction(b, f) {
  const cx = FRAME/2, cy = FRAME/2+6;
  b.ellipse(cx, 58, 20, 5, C(0,0,0,70));
  b.rrect(cx-22, cy-14, 44, 30, 5, C(70,66,60));
  b.rrect(cx-20, cy-12, 40, 26, 4, C(150,120,80));
  b.rrect(cx-20, cy-12, 40, 8, 3, C(180,150,100)); // 顶高光
  // 烟囱
  b.rrect(cx+12, cy-26, 8, 14, 2, C(60,58,56));
  // 冒烟（按帧上升）
  const smokeY = cy-26 - ((f*6) % 24);
  b.circle(cx+16, smokeY, 4+ (f%2), C(180,180,185,150));
  b.circle(cx+18, smokeY-8, 3, C(160,160,165,110));
  // 齿轮（旋转）
  const a = f/4*Math.PI*2;
  for (let i=0;i<6;i++){ const ang=a+i/6*Math.PI*2; b.line(cx-12, cy+2, cx-12+Math.cos(ang)*7, cy+2+Math.sin(ang)*7, C(110,90,60), 3); }
  b.circle(cx-12, cy+2, 6, C(130,105,70));
  b.circle(cx-12, cy+2, 2.5, C(80,64,44));
}

// 墙：混凝土块，frame1 裂纹
function drawWall(b, cracked) {
  const cx=FRAME/2, cy=FRAME/2;
  b.ellipse(cx, 58, 22, 5, C(0,0,0,60));
  b.rrect(cx-22, cy-22, 44, 44, 4, C(86,86,92));
  b.rrect(cx-20, cy-20, 40, 40, 3, C(118,118,124));
  // 砖缝
  b.line(cx-20, cy, cx+20, cy, C(70,70,76), 2);
  b.line(cx, cy-20, cx, cy, C(70,70,76), 2);
  b.line(cx-10, cy-20, cx-10, cy, C(70,70,76),1);
  b.line(cx+10, cy, cx+10, cy+20, C(70,70,76),1);
  if (cracked) {
    b.line(cx-14, cy-18, cx-4, cy-2, C(40,40,46), 2);
    b.line(cx-4, cy-2, cx+8, cy+6, C(40,40,46), 2);
    b.line(cx+8, cy+6, cx+14, cy+18, C(40,40,46), 2);
    b.line(cx-20, cy+10, cx-8, cy+14, C(40,40,46), 1.5);
  }
}

// 子弹：能量弹
function drawBullet(b) {
  const cx=FRAME/2, cy=FRAME/2;
  b.circle(cx, cy, 9, C(255,230,140,120));
  b.circle(cx, cy, 6, C(255,240,180,255));
  b.circle(cx-2, cy-2, 2.5, C(255,255,255,255));
}

// ---------- 输出精灵表 ----------
function sheet(name, cols, drawFn) {
  console.error(`[sheet] ${name} start (cols=${cols})`);
  const w = FRAME*cols, h = FRAME;
  const b = new Buf(w, h);
  for (let c=0;c<cols;c++) {
    const nb = new Buf(FRAME, FRAME);
    drawFn(nb, c);                  // 单帧画在 nb（坐标 0..FRAME）
    for (let y=0;y<FRAME;y++) {     // 逐行拼接到主表第 c 列
      const src = y*FRAME*4;
      const dst = (y*cols + c)*FRAME*4;
      b.d.set(nb.d.subarray(src, src+FRAME*4), dst);
    }
  }
  console.error(`[sheet] ${name} drew, encoding...`);
  const png = encodePNG(w, h, b.d);
  console.error(`[sheet] ${name} encoded ${png.length}B`);
  mkdirSync(OUT, { recursive: true });
  const file = `${OUT}/${name}.png`;
  writeFileSync(file, png);
  console.log(`  ${name}.png  ${w}x${h}  (${cols} 帧)`);
}

console.log('生成末日堡垒精灵表...');
sheet('zombie_walker', 4, (b,f)=>drawZombie(b,f,C(150,180,90),'walker'));
sheet('zombie_runner', 4, (b,f)=>drawZombie(b,f,C(200,80,70),'runner'));
sheet('zombie_spitter',4, (b,f)=>drawZombie(b,f,C(170,90,190),'spitter'));
sheet('turret_idle', 1, (b,f)=>drawTurret(b,0));
sheet('turret_fire', 4, (b,f)=>drawTurret(b,f));
sheet('core', 4, (b,f)=>drawCore(b,f));
sheet('production', 4, (b,f)=>drawProduction(b,f));
sheet('wall', 2, (b,f)=>drawWall(b, f===1));
sheet('bullet', 1, (b)=>drawBullet(b));
console.log('完成 ->', OUT);
