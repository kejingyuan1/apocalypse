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
  // 可平铺绘制：坐标环绕，用于无缝地面纹理
  setMod(x, y, c) {
    x = ((Math.round(x) % this.w) + this.w) % this.w;
    y = ((Math.round(y) % this.h) + this.h) % this.h;
    this.set(x, y, c);
  }
  rectMod(x, y, w, h, c) { for (let yy=0; yy<h; yy++) for (let xx=0; xx<w; xx++) this.setMod(x+xx, y+yy, c); }
  circleMod(cx, cy, r, c) { const r2=r*r; for (let yy=-r; yy<=r; yy++) for (let xx=-r; xx<=r; xx++) if (xx*xx+yy*yy<=r2) this.setMod(cx+xx, cy+yy, c); }
  lineMod(x0, y0, x1, y1, c, t=1) {
    x0=Math.round(x0); y0=Math.round(y0); x1=Math.round(x1); y1=Math.round(y1);
    const dx=Math.abs(x1-x0), dy=Math.abs(y1-y0), sx=x0<x1?1:-1, sy=y0<y1?1:-1;
    let err=dx-dy, x=x0, y=y0;
    while (true) {
      if (t<=1) this.setMod(x,y,c); else this.circleMod(x,y,t/2,c);
      if (x===x1 && y===y1) break;
      const e2=2*err;
      if (e2>-dy){ err-=dy; x+=sx; }
      if (e2<dx){ err+=dx; y+=sy; }
    }
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
// 重绘为更生动的末日丧尸：破烂衣物、腐烂细节、发光眼、动态四肢
function drawZombie(b, f, base, kind) {
  const cx = FRAME/2;
  const p = f/4 * Math.PI*2;
  const bob = Math.sin(p*2) * 2.2;          // 身体起伏
  const step = Math.sin(p) * 7;             // 腿部摆动
  const armSwing = Math.sin(p - 0.6) * 7;   // 手臂滞后摆动
  const torsoTilt = Math.cos(p*2) * 1.5;    // 躯干扭动
  // 根据类型调色
  let skin = base;
  let shirt = C(60,58,56);
  let pants = C(45,48,52);
  let glow = C(220,40,40);
  if (kind === 'runner') {
    skin = C(200,70,60);
    shirt = C(140,50,45);
    pants = C(80,40,38);
    glow = C(255,80,50);
  } else if (kind === 'spitter') {
    skin = C(130,170,90);
    shirt = C(55,70,50);
    pants = C(40,50,42);
    glow = C(160,255,80);
  }
  // 地面阴影（更柔和）
  b.ellipse(cx, 59, 18, 5, C(0,0,0,70));
  // 后腿（深色）
  const backLegX = cx - 6 + step * 0.9;
  const frontLegX = cx + 5 - step * 0.9;
  // 后腿
  b.line(cx-6, 42-bob, backLegX, 56, shade(pants,0.7), 6);
  b.ellipse(backLegX, 57, 5, 3, shade(pants,0.6));
  // 前腿
  b.line(cx+5, 42-bob, frontLegX, 56, pants, 6);
  b.ellipse(frontLegX, 57, 5, 3, shade(pants,0.85));
  // 躯干（更复杂轮廓：佝偻、前倾）
  const ty = 28 - bob;
  const tx = cx + torsoTilt;
  // 身体主体
  b.rrect(tx-12, ty-10, 24, 22, 7, shirt);
  // 破烂衣服下摆
  b.tri(tx-10, ty+12, tx-4, ty+18, tx+2, ty+12, shade(shirt,0.85));
  b.tri(tx+4, ty+12, tx+10, ty+17, tx+12, ty+12, shade(shirt,0.8));
  // 暴露的腐烂皮肤（腹部）
  b.rrect(tx-7, ty-4, 14, 12, 4, skin);
  b.circle(tx-3, ty+1, 2.5, shade(skin,0.65));
  b.circle(tx+4, ty-1, 2.0, shade(skin,0.7));
  // 肋骨/肌肉线条
  b.line(tx-5, ty-2, tx-5, ty+6, shade(skin,0.5), 1.5);
  b.line(tx+1, ty-2, tx+1, ty+6, shade(skin,0.55), 1.5);
  // 前伸手臂（丧尸特征）
  const armY1 = ty - 2 + armSwing * 0.25;
  const armY2 = ty + 6 - armSwing * 0.25;
  // 上臂
  b.line(tx+10, ty-2, tx+18, armY1, shade(shirt,0.75), 5);
  b.line(tx+10, ty+6, tx+18, armY2, shade(shirt,0.7), 5);
  // 前臂（前伸）
  b.line(tx+18, armY1, tx+26, armY1 + 2, shade(skin,0.85), 4);
  b.line(tx+18, armY2, tx+26, armY2 + 2, shade(skin,0.85), 4);
  // 手爪
  b.circle(tx+27, armY1 + 2, 3, shade(skin,0.9));
  b.circle(tx+27, armY2 + 2, 3, shade(skin,0.9));
  b.line(tx+28, armY1+2, tx+31, armY1+1, C(20,20,20), 1.5);
  b.line(tx+28, armY2+2, tx+31, armY2+3, C(20,20,20), 1.5);
  // 头（更大、更有特征）
  const hy = 8 - bob;
  const hx = tx + 2;
  b.circle(hx, hy, 11, skin);
  // 头发/秃顶
  b.circle(hx-2, hy-6, 5, C(50,50,48));
  b.circle(hx+4, hy-5, 4, C(55,55,52));
  // 顶光
  b.ellipse(hx-2, hy-5, 6, 3, shade(skin,1.18));
  // 深陷眼窝 + 发光眼
  b.circle(hx+4, hy-1, 3.5, C(12,12,14));
  b.circle(hx+4, hy-1, 1.8, glow);
  b.circle(hx+8, hy+1, 2.8, C(12,12,14));
  b.circle(hx+8, hy+1, 1.3, glow);
  // 鼻子（塌陷）
  b.circle(hx+7, hy+4, 1.8, shade(skin,0.55));
  // 嘴（张开）
  b.ellipse(hx+5, hy+8, 6, 3, C(20,10,10));
  b.line(hx+3, hy+8, hx+8, hy+9, C(160,40,40), 1.5);
  // 血迹/污渍
  b.circle(hx-3, hy+5, 2.2, C(130,30,30,160));
  b.circle(tx-8, ty+4, 3.0, C(120,30,30,140));

  // spitter 额外：背部毒囊 + 口部酸液
  if (kind === 'spitter') {
    const sacPulse = 1.0 + Math.sin(p*2) * 0.25;
    b.circle(tx-10, ty-2, 6*sacPulse, C(90,160,50));
    b.circle(tx-11, ty-3, 3*sacPulse, C(140,240,80));
    b.circle(tx-8, ty+5, 4*sacPulse, C(80,140,45));
    // 嘴边酸液滴
    const dripY = (hy+10) + (f%2)*3;
    b.circle(hx+6, dripY, 2.2, C(160,255,80,200));
  }
  // runner 额外：速度残影、更流线姿态
  if (kind === 'runner') {
    b.line(cx-16, ty-4, cx-22, ty-6, C(200,60,50,90), 3);
    b.line(cx-18, ty+4, cx-25, ty+2, C(200,60,50,70), 3);
    b.line(cx-14, 48-bob, cx-19, 48-bob, C(200,60,50,60), 2);
    // 更凶狠的眼睛
    b.circle(hx+4, hy-1, 2.0, C(255,120,60));
    b.circle(hx+8, hy+1, 1.5, C(255,120,60));
  }
  // walker 额外：蹒跚、更破烂
  if (kind === 'walker') {
    // 衣服破洞更大
    b.circle(tx-2, ty+2, 3.5, C(80,75,72));
    b.circle(tx+6, ty+5, 2.5, C(75,70,68));
    // 一只手臂下垂更厉害
    b.line(tx+10, ty+6, tx+20, ty+12, shade(skin,0.8), 4);
    b.circle(tx+21, ty+13, 2.5, shade(skin,0.9));
  }
}

// 通用：厚实墙体边框（俯视，左上高光/右下阴影，营造立体感）
function drawBunkerWall(b, t, wallColor) {
  const w = b.w, h = b.h;
  const light = shade(wallColor, 1.22);
  const mid   = shade(wallColor, 0.95);
  const dark  = shade(wallColor, 0.62);
  const innerShadow = shade(wallColor, 0.45);
  // 四边墙体（上/左亮，下/右暗，模拟顶光）
  b.rect(0, 0, w, t, light);      // 上边
  b.rect(0, 0, t, h, light);      // 左边
  b.rect(0, h - t, w, t, dark);   // 下边
  b.rect(w - t, 0, t, h, dark);   // 右边
  // 内部次层，让墙体有厚度
  b.rect(t, t, w - 2*t, h - 2*t, mid);
  // 四角加固块
  const c = t * 1.6;
  b.rect(0, 0, c, c, mid);
  b.rect(w - c, 0, c, c, mid);
  b.rect(0, h - c, c, c, mid);
  b.rect(w - c, h - c, c, c, mid);
  // 内沿阴影，强化“墙体高于地板”的空间感
  b.rect(t, t, w - 2*t, 3, innerShadow);
  b.rect(t, t, 3, h - 2*t, innerShadow);
}

// 通用：混凝土地砖/金属地板（带内网格与铆钉）
function drawRoomFloor(b, inset, floorColor, gridColor) {
  const w = b.w, h = b.h;
  b.rect(inset, inset, w - inset*2, h - inset*2, floorColor);
  // 地板接缝网格
  const cols = 3, rows = 3;
  for (let i=1;i<cols;i++) {
    const x = inset + i * (w - inset*2) / cols;
    b.line(x, inset, x, h - inset, gridColor, 1);
  }
  for (let i=1;i<rows;i++) {
    const y = inset + i * (h - inset*2) / rows;
    b.line(inset, y, w - inset, y, gridColor, 1);
  }
  // 随机铆钉/螺栓点缀
  for (let i=0;i<6;i++) {
    const rx = inset + 8 + (i%3) * ((w - inset*2)/3);
    const ry = inset + 8 + Math.floor(i/3) * ((h - inset*2)/3);
    b.circle(rx, ry, 2, shade(floorColor, 0.7));
  }
}

// 防御塔：拆成「底座」+「炮管」。底座不旋转；炮管单独精灵，由程序旋转。
// 防御塔阵地 3x3：厚实混凝土碉堡，完整墙体无缺口，中央转台、雷达、弹药箱
function drawTurretBase(b) {
  const w = b.w, h = b.h, cx = w/2, cy = h/2;
  const wallColor = C(108, 102, 88);
  const floorColor = C(58, 56, 52);
  const gridColor  = C(42, 40, 38);
  const t = 22;  // 墙体厚度

  // 厚实混凝土碉堡外墙（完整无缺口）
  drawBunkerWall(b, t, wallColor);
  // 内部地板
  drawRoomFloor(b, t + 4, floorColor, gridColor);

  // 中央圆形转台（金属质感）
  b.circle(cx, cy, 44, C(55, 58, 64));
  b.circle(cx, cy, 36, C(78, 82, 90));
  b.circle(cx, cy, 26, C(95, 100, 108));
  // 转台轨道槽
  for (let i=0;i<12;i++) {
    const a = i * Math.PI * 2 / 12;
    b.line(cx + Math.cos(a)*18, cy + Math.sin(a)*18,
           cx + Math.cos(a)*30, cy + Math.sin(a)*30, C(45, 48, 54), 2);
  }
  // 旋转轴凹槽（炮管底座）
  b.circle(cx, cy, 18, C(44, 50, 58));
  b.circle(cx, cy, 10, C(120, 200, 255, 180));

  // 后方雷达立柱
  const rx = w*0.78, ry = h*0.24;
  b.rrect(rx-6, ry-4, 12, 26, 2, C(70, 75, 82));
  b.circle(rx, ry-14, 10, C(80, 85, 92));
  b.line(rx-16, ry-14, rx+16, ry-14, C(60, 200, 120), 3);

  // 左侧弹药箱堆
  const ax = w*0.18, ay = h*0.74;
  for (let i=0; i<3; i++) {
    b.rrect(ax + i*14, ay - i*6, 16, 14, 2, C(95, 90, 78));
    b.line(ax + i*14 + 2, ay - i*6 + 7, ax + i*14 + 14, ay - i*6 + 7, C(70, 66, 58), 1);
  }

  // 右侧油桶
  const bx = w*0.83, by = h*0.72;
  b.ellipse(bx, by+13, 11, 4, C(0,0,0,80));
  b.rrect(bx-9, by-15, 18, 30, 3, C(95, 75, 55));
  b.line(bx-9, by-4, bx+9, by-4, C(70, 55, 40), 2);

  // 门口/观察窗：墙上缺口（不破坏整体轮廓，只增加识别度）
  b.rect(t + 4, h*0.45, 8, 22, C(35, 38, 42)); // 左墙内嵌窗
  b.rect(w - t - 12, h*0.40, 8, 18, C(35, 38, 42)); // 右墙内嵌窗
}

function drawTurretBarrel(b, fireFrame) {
  const cx = FRAME/2, cy = FRAME/2+4; // 旋转轴心与底座一致
  // 炮管朝 -y，根部在 (cx,cy)，顶端在 (cx, cy-30)
  b.rrect(cx-5, cy-30, 10, 30, 3, C(140,148,158));
  b.rrect(cx-4, cy-29, 8, 16, 2, C(180,188,198));
  b.circle(cx, cy-30, 6, C(90,96,104));
  // 炮口散热环
  b.rrect(cx-6, cy-34, 12, 5, 2, C(110,118,128));
  // 开火闪光（fireFrame: 0无 1大 2中 3小）
  if (fireFrame >= 1) {
    const fl = [0, 14, 9, 5][fireFrame] || 0;
    b.circle(cx, cy-36, fl, C(255,230,150,230));
    b.circle(cx, cy-36, fl*0.5, C(255,255,230,255));
    if (fireFrame === 1) {
      b.line(cx, cy-36, cx, cy-50, C(255,220,120,180), 3);
    }
  }
}

// 核心/指挥 4x4：《辐射》避难所式指挥中心，带厚实墙体、全息作战桌、电脑、椅子和脉动核心
function drawCore(b, f) {
  const w = b.w, h = b.h, cx = w/2, cy = h/2;
  const pulse = 0.5 + 0.5*Math.sin(f/4*Math.PI*2);
  const wallColor = C(95, 90, 84);
  const floorColor = C(52, 50, 46);
  const gridColor  = C(38, 36, 34);
  const t = 26;  // 指挥中心墙体更厚重

  // 厚实外墙 + 内部地板
  drawBunkerWall(b, t, wallColor);
  drawRoomFloor(b, t + 4, floorColor, gridColor);

  // 中央全息作战桌（闪烁）
  const tblW = (w - t*2)*0.55, tblH = (h - t*2)*0.35;
  b.ellipse(cx, cy + tblH*0.45, tblW*0.45, tblH*0.25, C(0,0,0,90));
  b.rrect(cx - tblW/2, cy - tblH/2, tblW, tblH, 6, C(55, 70, 85));
  b.rrect(cx - tblW/2 + 4, cy - tblH/2 + 4, tblW - 8, tblH - 8, 4, C(40, 55, 70));
  // 全息投影：旋转的战场扇区
  const spin = f/4*Math.PI*2;
  for (let i=0;i<3;i++) {
    const a1 = spin + i*Math.PI*2/3;
    const a2 = a1 + Math.PI/3;
    const r = tblH*0.28;
    const x1 = cx + Math.cos(a1)*r, y1 = cy + Math.sin(a1)*r*0.6;
    const x2 = cx + Math.cos(a2)*r, y2 = cy + Math.sin(a2)*r*0.6;
    b.tri(cx, cy, x1, y1, x2, y2, C(120, 200, 255, 90 + pulse*60));
  }
  b.circle(cx, cy, 6 + pulse*3, C(160, 220, 255, 140 + pulse*80));

  // 四台电脑（角落，屏幕闪烁）
  const screenGlow = 120 + pulse*80;
  const margin = t + 8;
  const corners = [[margin, margin], [w-margin-24, margin], [margin, h-margin-18], [w-margin-24, h-margin-18]];
  for (const [rx, ry] of corners) {
    b.rrect(rx, ry, 24, 18, 3, C(65, 62, 58));
    b.rrect(rx+3, ry+3, 18, 10, 2, C(screenGlow*0.4, screenGlow*0.55, screenGlow*0.7));
    b.line(rx+5, ry+6, rx+18, ry+6, C(180, 210, 230, 180), 1);
    b.line(rx+5, ry+9, rx+14, ry+9, C(180, 210, 230, 180), 1);
    b.rrect(rx+6, ry+20, 12, 8, 2, C(90, 55, 45));
  }

  // 顶部 status 灯带
  for (let i=0;i<5;i++) {
    const lx = cx - 40 + i*20;
    const on = (i + f) % 5 < 2;
    b.circle(lx, t + 6, 4, on ? C(255, 80, 60) : C(80, 70, 65));
  }
}

// 生产/储藏房 3x2：《辐射》式车间/储藏室，带厚实墙体、货架、桶、工作台、转动齿轮与蒸汽
function drawProduction(b, f) {
  const w = b.w, h = b.h, cx = w/2, cy = h/2;
  const wallColor = C(88, 84, 76);
  const floorColor = C(55, 53, 48);
  const gridColor  = C(40, 38, 35);
  const t = 18;  // 3x2 房间墙体厚度

  // 厚实外墙 + 内部地板
  drawBunkerWall(b, t, wallColor);
  drawRoomFloor(b, t + 3, floorColor, gridColor);

  // 左侧货架（储藏室特征）
  for (let row=0; row<3; row++) {
    const y = t + 10 + row*22;
    b.line(t + 8, y, t + 8 + w*0.36, y, C(95, 88, 78), 3);
    for (let item=0; item<4; item++) {
      const ix = t + 12 + item*16;
      const boxCol = (item + row) % 2 === 0 ? C(110, 95, 70) : C(90, 82, 72);
      b.rrect(ix, y - 14, 12, 12, 2, boxCol);
    }
  }
  // 右侧工作台
  const wx = w*0.58, wy = h*0.35;
  b.rrect(wx, wy, w*0.34, h*0.45, 3, C(85, 78, 68));
  // 台面上工具
  b.circle(wx + 16, wy + 12, 7, C(120, 120, 125)); // 盘子/仪表
  b.circle(wx + 16, wy + 12, 3, C(80, 200, 120, 160)); // 绿灯
  b.rrect(wx + 32, wy + 6, 16, 8, 2, C(100, 95, 88)); // 工具箱
  // 地面大齿轮（旋转动画）
  const gx = w*0.62, gy = h*0.72, gr = 18;
  const a = f/4*Math.PI*2;
  for (let i=0;i<8;i++) {
    const ang = a + i*Math.PI*2/8;
    b.line(gx, gy, gx + Math.cos(ang)*gr, gy + Math.sin(ang)*gr, C(95, 85, 70), 4);
  }
  b.circle(gx, gy, 8, C(75, 68, 58));
  b.circle(gx, gy, 3, C(45, 42, 38));
  // 蒸汽/烟雾（帧动画上升）
  const smokeY = t + 2 - ((f*8) % 28);
  b.circle(w*0.82, smokeY + 18, 5 + (f%2), C(180, 180, 185, 130));
  b.circle(w*0.85, smokeY + 6, 4, C(160, 160, 165, 100));
  // 桶
  b.ellipse(w*0.25, h - t - 6, 10, 5, C(0,0,0,80));
  b.rrect(w*0.25 - 8, h - t - 26, 16, 22, 3, C(90, 85, 75));
  b.line(w*0.25 - 8, h - t - 20, w*0.25 + 8, h - t - 20, C(70, 66, 58), 2);
}

// 墙：4 个等级，每级 2 帧（完好/破损）。level=0..3
function drawWall(b, frame) {
  const level = Math.floor(frame / 2);
  const cracked = (frame % 2) === 1;
  const cx=FRAME/2, cy=FRAME/2;
  // 各级颜色与材质
  const palettes = [
    {base: C(118,118,124), dark: C(86,86,92), seam: C(70,70,76), accent: C(95,95,100)}, // Lv1 混凝土
    {base: C(130,125,115), dark: C(95,90,82),  seam: C(72,68,62),  accent: C(150,145,135)}, // Lv2 加固石
    {base: C(110,120,130), dark: C(72,80,88),  seam: C(55,62,70),  accent: C(160,175,190)}, // Lv3 金属板
    {base: C(145,130,95),  dark: C(105,92,64), seam: C(82,72,52),  accent: C(210,185,120)}, // Lv4 合金装甲
  ];
  const pal = palettes[level];
  b.ellipse(cx, 58, 22, 5, C(0,0,0,60));
  // 主体
  b.rrect(cx-23, cy-23, 46, 46, 4, pal.dark);
  b.rrect(cx-21, cy-21, 42, 42, 3, pal.base);
  // 材质细节：等级越高越厚重
  if (level >= 1) {
    // 加固边框
    b.rrect(cx-18, cy-18, 36, 36, 2, pal.accent);
  }
  if (level >= 2) {
    // 金属铆钉
    for (const [bx,by] of [[cx-14,cy-14],[cx+14,cy-14],[cx-14,cy+14],[cx+14,cy+14]]) {
      b.circle(bx, by, 2.5, C(60,66,72));
      b.circle(bx, by, 1.2, C(140,150,160));
    }
  }
  if (level >= 3) {
    // 合金层 + 警示条纹
    b.rrect(cx-15, cy-15, 30, 30, 2, pal.accent);
    b.line(cx-12, cy-12, cx+12, cy+12, C(180,160,90), 3);
    b.line(cx+12, cy-12, cx-12, cy+12, C(180,160,90), 3);
  }
  // 砖缝/焊缝
  b.line(cx-21, cy, cx+21, cy, pal.seam, 2);
  b.line(cx, cy-21, cx, cy+2, pal.seam, 2);
  b.line(cx-10, cy-21, cx-10, cy+2, pal.seam, 1);
  b.line(cx+10, cy, cx+10, cy+21, pal.seam, 1);
  // 破损裂纹
  if (cracked) {
    const crackCol = level >= 3 ? C(60,55,40) : C(45,45,50);
    b.line(cx-15, cy-19, cx-5, cy-3, crackCol, 2.5);
    b.line(cx-5, cy-3, cx+9, cy+5, crackCol, 2.5);
    b.line(cx+9, cy+5, cx+15, cy+19, crackCol, 2.5);
    b.line(cx-21, cy+11, cx-9, cy+15, crackCol, 2);
    // 缺口
    b.circle(cx+14, cy-12, 4, pal.dark);
  }
  // 等级徽记（小圆点）
  for (let i=0;i<=level;i++) {
    b.circle(cx - 14 + i*7, cy + 16, 2, C(220,200,140));
  }
}

// 子弹：能量弹
function drawBullet(b) {
  const cx=FRAME/2, cy=FRAME/2;
  b.circle(cx, cy, 9, C(255,230,140,120));
  b.circle(cx, cy, 6, C(255,240,180,255));
  b.circle(cx-2, cy-2, 2.5, C(255,255,255,255));
}

// 地面细节覆盖层：512x512 可平铺裂纹/碎石纹理，解决放大后背景图模糊
function drawGroundTile(b) {
  const w = b.w, h = b.h;
  const base = C(108, 102, 94);
  // 基础色调（整数周期余弦，保证 512 边界处无缝平铺）
  const TAU = Math.PI * 2;
  for (let y=0; y<h; y++) {
    for (let x=0; x<w; x++) {
      const u = x / w, v = y / h;
      const n1 = Math.cos(TAU * u * 3) * Math.cos(TAU * v * 2);
      const n2 = Math.cos(TAU * (u + v) * 2);
      const n3 = Math.cos(TAU * u * 5) * Math.cos(TAU * v * 4);
      const vv = (n1 + n2 * 0.5 + n3 * 0.25) / 1.75;
      const f = 1.0 + vv * 0.16;
      b.rectMod(x, y, 1, 1, shade(base, f));
    }
  }
  // 裂纹（随机游走，可环绕）
  const crackCol = C(55, 52, 48, 180);
  for (let i=0; i<18; i++) {
    let x = Math.random() * w, y = Math.random() * h;
    const steps = 30 + Math.random() * 50;
    const seg = 8 + Math.random() * 12;
    for (let s=0; s<steps; s++) {
      const a = Math.random() * Math.PI * 2;
      const nx = x + Math.cos(a) * seg;
      const ny = y + Math.sin(a) * seg;
      b.lineMod(x, y, nx, ny, crackCol, 1 + Math.random()*1.5);
      x = nx; y = ny;
    }
  }
  // 碎石/小土块（可环绕）
  for (let i=0; i<120; i++) {
    const x = Math.random() * w, y = Math.random() * h;
    const r = 1 + Math.random() * 3;
    const c = Math.random() > 0.5 ? C(125, 118, 108) : C(85, 80, 74);
    b.circleMod(x, y, r, c);
  }
  // 更暗的污渍斑块
  for (let i=0; i<25; i++) {
    const x = Math.random() * w, y = Math.random() * h;
    const r = 8 + Math.random() * 20;
    b.circleMod(x, y, r, C(70, 66, 60, 60));
  }
}

// ---------- 输出精灵表 ----------
function sheet(name, cols, drawFn, fw=FRAME, fh=FRAME) {
  console.error(`[sheet] ${name} start (cols=${cols}, frame=${fw}x${fh})`);
  const w = fw*cols, h = fh;
  const b = new Buf(w, h);
  for (let c=0;c<cols;c++) {
    const nb = new Buf(fw, fh);
    drawFn(nb, c);                  // 单帧画在 nb（坐标 0..fw/fh）
    for (let y=0;y<fh;y++) {        // 逐行拼接到主表第 c 列
      const src = y*fw*4;
      const dst = (y*cols + c)*fw*4;
      b.d.set(nb.d.subarray(src, src+fw*4), dst);
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
// 房间精灵尺寸与 RoomDefs.size() 对应（TILE=64）：command 4x4=256x256, production 3x2=192x128, defense 3x3=192x192
sheet('turret_base',  1, (b,f)=>drawTurretBase(b), 192, 192);
sheet('turret_barrel', 4, (b,f)=>drawTurretBarrel(b,f));
sheet('core', 4, (b,f)=>drawCore(b,f), 256, 256);
sheet('production', 4, (b,f)=>drawProduction(b,f), 192, 128);
sheet('wall', 8, (b,f)=>drawWall(b, f));
sheet('bullet', 1, (b)=>drawBullet(b));
sheet('ground_detail', 1, (b,f)=>drawGroundTile(b), 512, 512);
console.log('完成 ->', OUT);
