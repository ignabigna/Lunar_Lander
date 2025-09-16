// Lunar Lander – HUD estilo Atari + Combustible + Puntuación + Terreno con textura
// Controles: ← → (rotar), SPACE (propulsor), ENTER/R (continuar/reiniciar)

int W = 800, H = 600;

PImage shipImg;
float shipScale = 1.0;
int nivel = 1;        // nivel actual
float gBase = 0.05;   // gravedad inicial

void settings() { size(W, H); }

// --- Nave y física ---
float x, y, vx, vy, rot;
float paso = PI/100.0;      // rotación fina
float g    = gBase;      // gravedad actual
float imp  = 0;             // impulso actual (seteado cuando hay thrust)
int ancho = 20, alto = 40;  // fallback geométrico
float shipR = 14;

// --- Colores (tema) ---
final color COL_FUEL_BAR    = color(255);         // barra de fuel (blanca)
final color COL_FUEL_BG     = color(40);          // fondo barra (gris oscuro)
final color COL_FUEL_BORDER = color(255);         // borde barra (blanco)
final color COL_THRUST      = color(255);         // fuego del propulsor (blanco)
final color COL_PAD         = color(25, 90, 40); // plataforma (verde sutil)

final color COL_GROUND      = color(60);          // suelo gris levemente clarito
final color COL_CRATER_IN   = color(52);          // interior del cráter
final color COL_CRATER_RIM1 = color(120);         // aro exterior
final color COL_CRATER_RIM2 = color(90);          // aro interior

// --- Cráteres ---
class Crater {
  float x, y, r, tilt;
  Crater(float x, float y, float r, float tilt) { this.x=x; this.y=y; this.r=r; this.tilt=tilt; }
}
ArrayList<Crater> craters = new ArrayList<Crater>();
int NUM_CRATERS = 14;  // cantidad por terreno

// --- Piedritas distribuidas en el área del terreno ---
ArrayList<PVector> pebbles = new ArrayList<PVector>();
ArrayList<Float>   pebSize = new ArrayList<Float>();
int NUM_PEBBLES = 240; // densidad

// Margen para que la textura NO toque el borde superior del terreno
final float TEX_MARGIN_TOP    = 20;  // px por debajo de la línea del terreno
final float TEX_MARGIN_BOTTOM = 5;  // px por encima del borde inferior de pantalla

// --- Combustible ---
float MAX_FUEL = 100;
float fuel = MAX_FUEL;
float BURN_PER_FRAME = 0.45;
boolean thrustHeld = false;

// --- Terreno y plataforma ---
float[] terreno;
int padX, padW = 80;
float padY;

// --- Estados ---
enum Estado { JUGANDO, ATERRIZADO_OK, ESTALLADO }
Estado estado = Estado.JUGANDO;

// --- Score / Tiempo por ronda ---
int score = 0;
int lastEarned = 0;       // puntos del último aterrizaje correcto
int roundStartMs = 0;
int roundShownMs = 0;     // tiempo congelado al finalizar la ronda

// Umbrales de aterrizaje correcto
float MAX_VX = 1.6;
float MAX_VY = 2.0;
float MAX_ANG = radians(12);
String[] shipFiles = { "ship1.png", "ship2.png", "ship3.png" };
int shipIndex = 2; // 0=ship1,1=ship2,2=ship3 → arranca con ship3


void setup() {
  generarTerreno();
  resetGame();                       // inicia la 1ª ronda
  shipImg = loadImage(shipFiles[shipIndex]);
  imageMode(CENTER);
  if (shipImg != null) shipR = max(shipImg.width, shipImg.height) * 0.25 * shipScale;

}

void draw() {
  background(0);
  dibujarEstrellas();
  dibujarTerreno();
  dibujarHUD(); // HUD + barra de fuel

  if (estado == Estado.JUGANDO) {
    // Entrada
    if (keyPressed && key == CODED) {
      if (keyCode == LEFT)  rot -= paso;
      if (keyCode == RIGHT) rot += paso;
    }

    // Thrust continuo si hay fuel
    if (thrustHeld && fuel > 0) {
      imp = 0.30;
      fuel -= BURN_PER_FRAME;
      if (fuel < 0) fuel = 0;
    } else {
      imp = 0;
    }

    // Física
    float ax = 0, ay = g;
    if (imp > 0) {
      ax += imp * sin(rot);
      ay += -imp * cos(rot);
    }
    vx += ax; vy += ay;
    vx *= 0.995; vy *= 0.995;

    x = (x + vx + width) % width;
    y += vy;

    // Colisión con el terreno
    float groundY = yTerreno(x);
    if (y + shipR >= groundY) {
      y = groundY - shipR;

      boolean sobrePad = x >= padX && x <= padX + padW;
      boolean velOk = abs(vx) <= MAX_VX && abs(vy) <= MAX_VY;
      float angNorm = (rot % TWO_PI + TWO_PI) % TWO_PI;
      if (angNorm > PI) angNorm -= TWO_PI; // [-PI, PI]
      boolean angOk = abs(angNorm) <= MAX_ANG;

      if (sobrePad && velOk && angOk) {
        estado = Estado.ATERRIZADO_OK;
        lastEarned = calcularPuntos();
      } else {
        estado = Estado.ESTALLADO;
        lastEarned = 0;
      }

      vx = vy = 0;
      imp = 0;
      thrustHeld = false;
      roundShownMs = millis() - roundStartMs; // congelamos tiempo de la ronda
    }
  }

  // Dibujo de la nave (permanece en cualquier estado)
  dibujarNave();

  // Cartel de estado (overlay)
  dibujarCartelEstado();
}

// ========================= Entrada =========================
void keyPressed() {
  // Propulsor continuo
  if (key == ' ') {
    thrustHeld = true;
    return;
  }

  // Reinicio/avance con R (NO cambia skin)

  if (keyCode == ENTER || keyCode == RETURN) {
    if (estado == Estado.JUGANDO) {
      // reinicia SOLO la ronda actual (mismo terreno, mismo score, misma skin)
      resetGame();
    } else {
      // ronda terminada → aplica progreso y NUEVO terreno, misma skin
      if (estado == Estado.ATERRIZADO_OK) {
        score += lastEarned;
        nivel++;
        g += 0.002;
      } else {
        score = 0;
        nivel = 1;
        g = gBase;
      }
      generarTerreno();
      resetGame();
    }
    return;
  }

  // Reinicio/avance con ENTER/RETURN (SÍ cambia skin)
  if (key == 'r' || key == 'R') {
    if (estado == Estado.JUGANDO) {
      // jugando: cambia skin y reinicia la ronda (mismo terreno/score)
      shipIndex = (shipIndex + 1) % shipFiles.length;
      shipImg = loadImage(shipFiles[shipIndex]);
      if (shipImg != null) shipR = max(shipImg.width, shipImg.height) * 0.25 * shipScale;
      resetGame();
    } else {
      // ronda terminada: aplica progreso, NUEVO terreno y cambia skin
      if (estado == Estado.ATERRIZADO_OK) {
        score += lastEarned;
        nivel++;
        g += 0.002;
      } else {
        score = 0;
        nivel = 1;
        g = gBase;
      }
      shipIndex = (shipIndex + 1) % shipFiles.length;
      shipImg = loadImage(shipFiles[shipIndex]);
      if (shipImg != null) shipR = max(shipImg.width, shipImg.height) * 0.25 * shipScale;

      generarTerreno();
      resetGame();
    }
  }
}


void keyReleased() { if (key == ' ') thrustHeld = false; }

// ===================== Utilidades ==========================
void resetGame() {
  x = random(width);
  y = random(40, 120);
  vx = 0; vy = 0.5;
  rot = 0;
  fuel = MAX_FUEL;
  estado = Estado.JUGANDO;
  lastEarned = 0;
  roundStartMs = millis();
  roundShownMs = 0;
}

int calcularPuntos() {
  // Base + bonus por combustible y suavidad del toque
  int base = 100;
  int bonusFuel = int(fuel);
  int suavidad = int(max(0, 150 - (abs(vx)*60*25 + abs(vy)*60*40)));
  return max(50, base + bonusFuel + suavidad);
}

void generarTerreno() {
  terreno = new float[width];
  float nx = random(1000);
  float escala = 0.008;
  float base = height*0.72;
  float amp  = 120;

  for (int i=0; i<width; i++) {
    float h = base + (noise(nx) - 0.5)*2*amp;
    terreno[i] = constrain(h, height*0.45, height*0.95);
    nx += escala;
  }
  // Plataforma plana
  padX = int(random(80, width-80-padW));
  padY = min(terreno[padX], terreno[padX+padW-1]);
  for (int i=padX; i<padX+padW; i++) terreno[i] = padY;

  // Texturas
  generarCraters();
  generarPebbles();
}

void generarCraters() {
  craters.clear();
  for (int i = 0; i < NUM_CRATERS; i++) {
    float r  = random(10, 26);
    float cx = random(24, width - 24);

    // Profundidad mínima para evitar el perímetro superior del terreno
    float top = yTerreno(cx);
    // Centro del cráter siempre por DEBAJO de la línea del terreno
    float depth = random(TEX_MARGIN_TOP + r*0.2, TEX_MARGIN_TOP + r*1.2);
    float cy = constrain(top + depth, top + TEX_MARGIN_TOP, height - TEX_MARGIN_BOTTOM);

    // Evitar que queden sobre la plataforma
    if (cx > padX - 20 && cx < padX + padW + 20) { i--; continue; }

    float tilt = random(-0.25, 0.25);
    craters.add(new Crater(cx, cy, r, tilt));
  }
}


void generarPebbles() {
  pebbles.clear();
  pebSize.clear();
  for (int i = 0; i < NUM_PEBBLES; i++) {
    float px = random(0, width);
    float top = yTerreno(px);
    // Distribuir bien adentro del suelo
    float py = random(top + TEX_MARGIN_TOP, height - TEX_MARGIN_BOTTOM);
    pebbles.add(new PVector(px, py));
    pebSize.add(random(1, 2.3));
  }
}


float yTerreno(float xf) {
  int xi = int(constrain(xf, 0, width-1));
  return terreno[xi];
}

// ===================== Dibujo ==============================
void dibujarTerreno() {
  // Suelo relleno (gris claro)
  stroke(200);
  fill(COL_GROUND);
  beginShape();
  for (int i=0; i<width; i++) vertex(i, terreno[i]);
  vertex(width, height);
  vertex(0, height);
  endShape(CLOSE);

  // Textura: piedritas en el área del suelo
  dibujarPebbles();

  // Cráteres
  dibujarCraters();

  // Plataforma (verde sutil)
  stroke(COL_PAD);
  strokeWeight(2);
  line(padX, padY, padX+padW, padY);
  strokeWeight(1);
}

void dibujarPebbles() {
  noStroke();
  for (int i=0; i<pebbles.size(); i++) {
    PVector p = pebbles.get(i);
    float s = pebSize.get(i);
    fill(220, 220, 220, 55); // puntitos tenues, más claros que el suelo
    rect(p.x, p.y, s, s);
  }
}

void dibujarCraters() {
  for (Crater c : craters) dibujarCrater(c);
}

void dibujarCrater(Crater c) {
  if (c.x < -50 || c.x > width + 50) return;

  pushMatrix();
  translate(c.x, c.y);
  rotate(c.tilt);

  // Interior oscuro con algo de transparencia (parche en el suelo)
  noStroke();
  fill(COL_CRATER_IN, 75);
  ellipse(0, 0, c.r*1.6, c.r*1.0);

  // Aros muy finos y semitransparentes ()
  noFill();
  stroke(COL_CRATER_RIM1, 120); strokeWeight(1.2);
  ellipse(0, 0, c.r*1.6, c.r*1.0);

  stroke(COL_CRATER_RIM2, 110); strokeWeight(0.9);
  ellipse(0, 0, c.r*1.25, c.r*0.8);
  popMatrix();
}


void dibujarEstrellas() {
  stroke(255, 180);
  for (int i=0; i<60; i++) point((frameCount*3 + i*73) % width, (i*47) % height);
}

void dibujarHUD() {
  int y0 = 18, dy = 16;

  // -------- Columna izquierda: SCORE / TIME / FUEL / LEVEL / GRAVITY ----------
  pushStyle();
  fill(255);
  textAlign(LEFT);
  textSize(12);

  int lx = 10;

  text("SCORE", lx, y0);
  text(nf(score, 5), lx + 70, y0);

  text("TIME", lx, y0 + dy);
  int ms = (estado == Estado.JUGANDO) ? millis() - roundStartMs : roundShownMs;
  text(formatoTiempo(ms), lx + 70, y0 + dy);

  text("FUEL", lx, y0 + 2*dy);
  text(nf(int(fuel), 3), lx + 70, y0 + 2*dy);

  // nuevos: nivel y gravedad
  text("LEVEL", lx, y0 + 3*dy);
  text(nf(nivel, 2), lx + 70, y0 + 3*dy);

  text("GRAVITY", lx, y0 + 4*dy);
  text(nfc(g, 3), lx + 70, y0 + 4*dy);
  popStyle();

  // -------- Columna derecha: ALTITUDE / H-SPEED / V-SPEED ----
  pushStyle();
  fill(255);
  textAlign(LEFT);
  textSize(12);

  int rx = width - 240;
  float alt = max(0, yTerreno(x) - (y + shipR));
  float hs  = vx * 60.0; // px/seg aprox
  float vs  = vy * 60.0;

  String arrH = hs > 1 ? "→" : hs < -1 ? "←" : "";
  String arrV = vs > 1 ? "↓" : vs < -1 ? "↑" : "";

  text("ALTITUDE", rx, y0);
  text(nf(int(alt), 4), rx + 160, y0);

  text("HORIZONTAL SPEED", rx, y0 + dy);
  text(nf(abs(int(hs)), 3) + "  " + arrH, rx + 160, y0 + dy);

  text("VERTICAL SPEED", rx, y0 + 2*dy);
  text(nf(abs(int(vs)), 3) + "  " + arrV, rx + 160, y0 + 2*dy);

  // ---- Barra de combustible al lado derecho ----
  int bx = rx;                 // arranca en la columna derecha
  int by = y0 + 3*dy + 8;      // debajo de los 3 renglones de la derecha
  int bw = 160, bh = 12;
  noStroke();                  fill(COL_FUEL_BG);     rect(bx, by, bw, bh);
  float ratio = fuel / MAX_FUEL;
  fill(COL_FUEL_BAR);         rect(bx, by, bw * ratio, bh);
  stroke(COL_FUEL_BORDER);    noFill();               rect(bx, by, bw, bh);
  // Etiqueta pequeña para la barra (opcional)
  noStroke(); fill(255);       text("FUEL", bx, by - 4);

  popStyle();
}


void dibujarNave() {
  pushMatrix();
  translate(x, y);
  rotate(rot);
  noStroke();

  if (estado == Estado.ATERRIZADO_OK)      tint(0, 230, 0);
  else if (estado == Estado.ESTALLADO)     tint(230, 40, 30);
  else                                     tint(255);

  if (shipImg != null) {
    image(shipImg, 0, 0, shipImg.width*shipScale, shipImg.height*shipScale);
  } else {
    // fallback geométrico
    fill(255); rectMode(CENTER);
    triangle(-ancho/2, -alto/2, ancho/2, -alto/2, 0, -alto);
    rect(0, 0, ancho, alto);
  }

  // Fuego del propulsor
  if (estado == Estado.JUGANDO && imp > 0) {
    noTint();
    fill(COL_THRUST);   // blanco
    float h = (shipImg != null) ? shipImg.height*shipScale*0.5 : alto*0.5;
    triangle(-6, h, 6, h, 0, h + random(10, 22));
  }
  popMatrix();
}

void dibujarCartelEstado() {
  if (estado == Estado.JUGANDO) return;

  String msg = (estado == Estado.ATERRIZADO_OK) ? "¡Aterrizaje correcto!" : "¡Impacto!";
  if (estado == Estado.ATERRIZADO_OK && lastEarned > 0) msg += "  (+" + lastEarned + ")";

  int yMsg = 100; // 50 px debajo del HUD
  pushStyle();
  textAlign(CENTER);
  textSize(12);
  rectMode(CENTER);
  noStroke();
  fill(0, 160);
  float w = textWidth(msg) + textWidth("   (ENTER o R para continuar)") + 32;
  float h = 24;
  rect(width/2, yMsg - 6, w, h, 6);

  fill(255);
  text(msg + "   (ENTER o R para continuar)", width/2, yMsg);
  popStyle();
}

// --------------------- Helpers -----------------------------
String formatoTiempo(int ms) {
  int s = max(0, ms/1000);
  int mm = s/60;
  int ss = s%60;
  return nf(mm, 2) + ":" + nf(ss, 2);
}
