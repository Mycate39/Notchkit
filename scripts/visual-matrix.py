#!/usr/bin/env python3
"""Banc d'essai visuel : filme la vraie encoche (mode démo, build Debug) dans toutes les combinaisons
de widget, de taille de widget et de style d'animation, puis prépare l'analyse.

Usage :
  python3 scripts/visual-matrix.py scenarios   # écrit les scénarios dans build.noindex/visual-matrix/
  python3 scripts/visual-matrix.py record [prise…]   # tourne (Notchkit doit être quitté)
  python3 scripts/visual-matrix.py analyze [prise…]  # images fixes, planches et mesure des animations
  python3 scripts/visual-matrix.py spaces      # diagnostic : changements de bureau (Ctrl ←/→) pendant
                                               la musique, son réel capté ; analyse des barres et de l'encoche
  python3 scripts/visual-matrix.py animations  # mêmes animations avant tout changement de bureau, puis après
                                               chacun : comparaison image par image avec la référence
  --only widget,widget…   (avec scenarios / record) : seulement ces widgets et les pages mélangées,
                          sans les styles d'animation (vérification rapide d'une correction)

Une seule prise (la largeur de l'encoche suit les widgets), qui enchaîne :
  1. chaque widget seul, dans chaque taille (Mini, Petit, Moyen, Grand) : ouverture, pause, fermeture ;
  2. des pages mélangées (tirage fixe) ;
  3. chaque style d'animation (Fluide, Rapide, Rebondissante, Aucune) : ouverture, pages, fermeture,
     bulle survolée, indicateur de volume, déverrouillage.
"""
import json, os, random, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "build.noindex", "visual-matrix")
APP = os.path.join(ROOT, "build.noindex/DerivedData/Build/Products/Debug/Notchkit.app/Contents/MacOS/Notchkit")

# Widgets de la disposition (la webcam est écartée : elle allumerait la caméra pendant le tournage).
WIDGETS = ["music", "clock", "battery", "calendar", "weather", "activities", "clipboard", "shelf", "screenshots",
           "converter", "toggles", "dayprogress", "notes", "todo", "sysmon", "dashboard", "screentime", "health",
           "translation", "airpods", "systemhud", "videodownload"]
SIZES = ["mini", "small", "medium", "large"]
ANIMATIONS = ["fluid", "quick", "bouncy", "none"]
# Plus de taille d'encoche à choisir : sa largeur suit les widgets de la page. Une seule prise.
NOTCHES = {"auto": {}}
OTHER_MODULES = ["agents", "claude", "unlock", "gamemode"]

# Données factices posées au début (aucune donnée réelle de l'utilisateur n'est filmée).
SEED = [
    {"do": "music.play", "title": "danker", "artist": "Gabester"},
    {"do": "weather.set"}, {"do": "calendar.set"}, {"do": "todo.set"}, {"do": "clipboard.set"},
    {"do": "notes.set"}, {"do": "screentime.set"}, {"do": "health.set"}, {"do": "translation.set"},
    {"do": "monitor.sample"}, {"do": "shelf.add", "items": ["Mockup.pdf", "Photo.jpg"]}, {"do": "screenshot"},
    {"do": "timer.start", "minutes": 25}, {"do": "download.start", "title": "Notchkit 2.0", "level": 900},
    {"do": "claude.work", "project": "website"}, {"do": "converter.done", "items": ["Photo.jpg"]},
]


def scenario(notch, only=None, glass=False):
    steps, t = [], 0.5
    for seed in SEED:
        steps.append(dict(seed, at=round(t, 2)))
        t += 0.15
    t = 7.0
    marks = []

    def add(at, action, **params):
        steps.append(dict(params, at=round(at, 2), **{"do": action}))

    def combo(label, pages, sizes):
        nonlocal t
        add(t, "settings.layout", pages=pages, sizes=sizes)
        add(t + 0.4, "expand", module=pages[0][0])
        marks.append({"label": label, "expand": round(t + 0.4, 2), "still": round(t + 1.6, 2), "collapse": round(t + 1.9, 2)})
        add(t + 1.9, "collapse")
        t += 2.6

    # 1. Chaque widget seul, dans chaque taille ; la page Agents n'a qu'une taille.
    for widget in only or WIDGETS:
        for size in SIZES:
            combo(f"{widget}/{size}", [[widget]], {widget: size})
    if not only:
        combo("agents/page", [["agents"]], {})

    # 2. Pages mélangées (tirage fixe : mêmes pages à chaque tournage).
    rng = random.Random(42)
    for i in range(14):
        chosen = rng.sample(WIDGETS, rng.randint(2, 4))
        sizes = {w: rng.choice(SIZES) for w in chosen}
        combo("mix/" + "+".join(f"{w}:{sizes[w]}" for w in chosen), [chosen], sizes)

    # 3. Styles d'animation, sur trois pages.
    pages = [["music", "weather", "calendar"], ["activities", "sysmon"], ["agents"]]
    for anim in [] if only or glass else ANIMATIONS:
        add(t, "settings.animation", value=anim)
        add(t + 0.1, "settings.layout", pages=pages, sizes={"music": "medium"})
        start = t + 0.5
        add(start, "expand", module="music")
        add(start + 1.3, "page", page=1)
        add(start + 2.3, "page", page=2)
        add(start + 3.3, "page", page=0)
        add(start + 4.3, "collapse")
        add(start + 5.3, "bubble.hover")
        add(start + 6.6, "bubble.leave")
        add(start + 7.4, "hud.volume", level=0.7)
        add(start + 9.4, "unlock")
        marks.append({"label": f"anim/{anim}", "start": round(start, 2), "end": round(start + 12.4, 2)})
        t = start + 12.9
    add(t, "end")
    setup = dict(NOTCHES[notch], modules=WIDGETS + OTHER_MODULES, pages=[["music"]])
    if glass:
        setup["background"] = "glass"
    return {"duration": round(t + 0.5, 2), "region": {"width": 1100, "height": 360}, "fps": 60,
            "setup": setup, "steps": steps}, marks


def write_scenarios(only=None):
    for notch in NOTCHES:
        folder = os.path.join(OUT, notch)
        os.makedirs(folder, exist_ok=True)
        data, marks = scenario(notch, only)
        json.dump(data, open(os.path.join(folder, "scenario.json"), "w"), indent=1)
        json.dump(marks, open(os.path.join(folder, "marks.json"), "w"), indent=1)
        print(f"{notch} : {len(marks)} essais, {data['duration'] / 60:.1f} min")


def record(names):
    if subprocess.run(["pgrep", "-f", "Notchkit.app/Contents/MacOS/Notchkit"], capture_output=True).returncode == 0:
        sys.exit("NOTCHKIT-OUVERT : quittez Notchkit (et l'instance lancée depuis Xcode) avant le tournage.")
    for notch in names:
        folder = os.path.join(OUT, notch)
        env = dict(os.environ, NOTCHKIT_DEMO=os.path.join(folder, "scenario.json"), NOTCHKIT_DEMO_OUTPUT=folder)
        print(f"Tournage {notch}…", flush=True)
        result = subprocess.run([APP, "-module.claude.port", "52797", "-AppleLanguages", "(fr)"], env=env,
                                capture_output=True, text=True)
        lines = [l for l in result.stderr.splitlines() if "DEMO" in l]
        print("\n".join(lines) or "(aucune sortie DEMO)", flush=True)
        # ProRes 4444 très lourd : version H.264 sur fond gris pour l'analyse, puis suppression.
        mov = os.path.join(folder, "notch.mov")
        if os.path.exists(mov):
            subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", mov, "-filter_complex",
                            "color=c=0x6E6E78:s=2200x720:r=60[bg];[bg][0:v]overlay=shortest=1,format=yuv420p",
                            "-c:v", "libx264", "-crf", "14", "-preset", "fast", os.path.join(folder, "notch.mp4")], check=True)
            os.remove(mov)


def actual_times(folder):
    """Instant réel (dans la vidéo) de chaque étape prévue : `planned` → `at` de timeline.json."""
    steps = json.load(open(os.path.join(folder, "timeline.json")))["steps"]
    return {round(s["planned"], 2): s["at"] for s in steps}


def frame_diffs(video, start, duration):
    """Écart moyen entre images successives (0–255) sur une fenêtre de la vidéo, une valeur par image."""
    out = subprocess.run(["ffmpeg", "-v", "error", "-ss", str(start), "-t", str(duration), "-i", video, "-vf",
                          "scale=550:-1,tblend=all_mode=difference,signalstats,"
                          "metadata=print:key=lavfi.signalstats.YAVG:file=-", "-f", "null", "-"],
                         capture_output=True, text=True).stdout
    return [float(l.split("=")[1]) for l in out.splitlines() if "YAVG=" in l]


def motion_report(diffs, still=0.02):
    """Durée du mouvement, images figées au milieu du mouvement (saccades) et plus grand saut."""
    moving = [i for i, d in enumerate(diffs) if d > still]
    if not moving:
        return {"frames": 0, "stalls": 0, "jump": 0}
    first, last = moving[0], moving[-1]
    window = diffs[first:last + 1]
    # Saccade : image figée en plein mouvement (voisines qui bougent nettement), à l'instant `at` (s)
    stalls = [round((first + i) / 60, 3) for i in range(1, len(window) - 1)
              if window[i] <= still and window[i - 1] > 0.3 and window[i + 1] > 0.3]
    # Saut : image qui bouge beaucoup plus que ses voisines (élément qui « téléporte »), hors rattrapage
    # d'une saccade (l'image qui suit une image figée bouge naturellement du double)
    jump = max((d / max((window[i - 1] + window[i + 1]) / 2, 0.05) for i, d in enumerate(window)
                if 1 < i < len(window) - 1 and window[i - 1] > still), default=0)
    return {"frames": last - first + 1, "stalls": stalls, "jump": round(jump, 1)}


def analyze(names):
    sheet_tool = os.path.join(OUT, "contact-sheet")
    subprocess.run(["swiftc", "-O", os.path.join(ROOT, "scripts", "contact-sheet.swift"), "-o", sheet_tool], check=True)
    for notch in names:
        folder = os.path.join(OUT, notch)
        video = os.path.join(folder, "notch.mp4")
        if not os.path.exists(video):
            print(f"{notch} : pas de prise")
            continue
        times = actual_times(folder)
        marks = json.load(open(os.path.join(folder, "marks.json")))
        stills = os.path.join(folder, "stills")
        os.makedirs(stills, exist_ok=True)
        report, cells = [], []
        for i, mark in enumerate(marks):
            label = mark["label"]
            if "expand" in mark:
                expand = times.get(mark["expand"], mark["expand"])
                collapse = times.get(mark["collapse"], mark["collapse"])
                png = os.path.join(stills, f"{i:03d}.png")
                subprocess.run(["ffmpeg", "-v", "error", "-y", "-ss", str(expand + 1.2), "-i", video, "-frames:v", "1",
                                "-vf", "scale=1100:-1", png], check=True)
                cells.append((png, label))
                opening = motion_report(frame_diffs(video, expand - 0.05, 0.9))
                closing = motion_report(frame_diffs(video, collapse - 0.05, 0.9))
                report.append({"label": label, "opening": opening, "closing": closing})
            else:
                start = times.get(mark["start"], mark["start"])
                diffs = frame_diffs(video, start - 0.05, mark["end"] - mark["start"])
                report.append({"label": label, "sequence": motion_report(diffs), "diffs": [round(d, 2) for d in diffs]})
                # Images de la séquence d'animation : une toutes les 0,1 s pendant l'ouverture et les pages
                seq = os.path.join(folder, label.replace("/", "-"))
                os.makedirs(seq, exist_ok=True)
                subprocess.run(["ffmpeg", "-v", "error", "-y", "-ss", str(start - 0.05), "-t", "12.4", "-i", video,
                                "-vf", "fps=10,scale=1100:-1", os.path.join(seq, "%03d.png")], check=True)
        json.dump(report, open(os.path.join(folder, "report.json"), "w"), indent=1)
        # Planches : 4 colonnes (Mini, Petit, Moyen, Grand pour les widgets seuls), 6 rangées par planche
        for n in range(0, len(cells), 24):
            chunk = cells[n:n + 24]
            args = [a for cell in chunk for a in cell]
            subprocess.run([sheet_tool, os.path.join(folder, f"planche-{n // 24 + 1}.png"), "4", "700", *args], check=True)
        print(f"{notch} : {len(cells)} images fixes, rapport dans {folder}/report.json", flush=True)


# MARK: - Diagnostic des changements de bureau

MUSIC = os.path.expanduser("~/Documents/Projets/Notchkit-video/assets/music/danker.mp3")
# Changements de bureau (secondes de la prise, sens) : repliée, ouverte, en rafale, puis lents.
SWITCHES = ([(8 + 4 * i, "right" if i % 2 == 0 else "left") for i in range(10)]
            + [(52, "right"), (55, "left"), (58, "right")]
            + [(64, "left"), (65, "right"), (66, "left"), (67, "right")]
            + [(72 + 5 * i, "left" if i % 2 == 0 else "right") for i in range(4)])
SPACES_DURATION = 96


def spaces_scenario():
    steps = [{"at": 1.0, "do": "music.play", "title": "danker", "artist": "Gabester"},
             {"at": 50.0, "do": "expand", "module": "music"}, {"at": 61.0, "do": "collapse"},
             {"at": SPACES_DURATION - 1, "do": "end"}]
    return {"duration": SPACES_DURATION, "region": {"width": 1100, "height": 360}, "fps": 60,
            "setup": {"modules": ["music"], "pages": [["music"]]}, "steps": steps}


def record_spaces(name="spaces", scenario=None, switches=None, duration=None, extra_env=None, shots=(), music=True):
    scenario = scenario or spaces_scenario()
    switches = SWITCHES if switches is None else switches
    duration = duration or scenario["duration"]
    if subprocess.run(["pgrep", "-f", "Notchkit.app/Contents/MacOS/Notchkit"], capture_output=True).returncode == 0:
        sys.exit("NOTCHKIT-OUVERT : quittez Notchkit (et l'instance lancée depuis Xcode) avant le tournage.")
    import time
    folder = os.path.join(OUT, name)
    os.makedirs(folder, exist_ok=True)
    json.dump(scenario, open(os.path.join(folder, "scenario.json"), "w"), indent=1)
    env = dict(os.environ, NOTCHKIT_DEMO=os.path.join(folder, "scenario.json"), NOTCHKIT_DEMO_OUTPUT=folder,
               NOTCHKIT_DIAGNOSTIC="1", **(extra_env or {}))
    print("Tournage des changements de bureau…", flush=True)
    app = subprocess.Popen([APP, "-module.claude.port", "52797", "-AppleLanguages", "(fr)"], env=env,
                           stderr=subprocess.PIPE, text=True)
    player = subprocess.Popen(["afplay", "-t", str(duration + 6), MUSIC] if music else ["true"])
    launched = time.time()
    # La prise démarre environ 2,5 s après le lancement (mise en place des modules).
    switched = []
    # Changements de bureau et vraies captures d'écran macOS (contrôle de l'enregistrement), dans l'ordre
    events = sorted([(at, "switch", d) for at, d in switches] + [(at, "shot", None) for at in shots])
    for at, kind, direction in events:
        wait = launched + 2.5 + at - time.time()
        if wait > 0:
            time.sleep(wait)
        if kind == "shot":
            subprocess.run(["screencapture", "-x", "-R", os.environ.get("NOTCHKIT_SHOT_RECT", "600,0,600,220"), os.path.join(folder, f"shot-{at:05.1f}.png")])
            continue
        code = 124 if direction == "right" else 123
        subprocess.run(["osascript", "-e", f'tell application "System Events" to key code {code} using control down'])
        switched.append({"epoch": time.time(), "direction": direction})
    _, err = app.communicate()
    player.terminate()
    print("\n".join(l for l in err.splitlines() if "DEMO" in l), flush=True)
    open(os.path.join(folder, "diag.log"), "w").write("\n".join(l for l in err.splitlines() if "DEMO-DIAG" in l))
    timeline = json.load(open(os.path.join(folder, "timeline.json")))
    for s in switched:
        s["at"] = round(s["epoch"] - timeline["startedAt"], 3)
    json.dump(switched, open(os.path.join(folder, "switches.json"), "w"), indent=1)
    mov = os.path.join(folder, "notch.mov")
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", mov, "-filter_complex",
                    "color=c=0x6E6E78:s=2200x720:r=60[bg];[bg][0:v]overlay=shortest=1,format=yuv420p",
                    "-c:v", "libx264", "-crf", "14", "-preset", "fast", os.path.join(folder, "notch.mp4")], check=True)
    os.remove(mov)


# Série d'animations rejouée avant tout changement de bureau (référence), puis après chacun.
# (décalage dans la série, action, paramètres, nom de la fenêtre mesurée, durée de la fenêtre)
ANIMATION_SET = [
    (0.0, "expand", {"module": "music"}, "ouverture", 1.2),
    (1.2, "page", {"page": 1}, "page", 1.2),
    (2.4, "collapse", {}, "fermeture", 1.0),
    (3.4, "bubble.hover", {}, "bulle-survol", 1.2),
    (4.6, "bubble.leave", {}, "bulle-retour", 0.8),
    (5.4, "hud.volume", {"level": 0.7}, "volume", 2.0),
    (7.4, "unlock", {}, "face-id", 2.6),
]
ANIMATION_BLOCK = 11.0
# Avant chaque série (sauf la première) : changements de bureau à faire, en secondes avant la série.
ANIMATION_SWITCHES = [None, [("right", 1.5)], [("left", 1.5)], [("right", 1.5)], [("left", 0.4)],
                      [("right", 3.5), ("left", 2.5), ("right", 1.5)], [("left", 1.5)]]


# Changement de bureau PENDANT une animation : (décalage dans la série) ; la série 0 sert de référence.
DURING = [None, 0.15, 1.35, 2.55, 3.55, 4.7, 5.6, 7.7, 8.2]


def during_test():
    steps = [{"at": 0.5, "do": "music.play", "title": "danker", "artist": "Gabester"},
             {"at": 0.8, "do": "timer.start", "minutes": 25}]
    switches, blocks, t = [], [], 4.0
    for i, offset in enumerate(DURING):
        if offset is not None:
            switches.append((round(t + offset, 2), "right" if i % 2 else "left"))
        for off, action, params, _, _ in ANIMATION_SET:
            steps.append(dict(params, at=round(t + off, 2), **{"do": action}))
        blocks.append(round(t, 2))
        t += ANIMATION_BLOCK + 1.5
    steps.append({"at": round(t, 2), "do": "end"})
    scenario = {"duration": round(t + 0.5, 2), "region": {"width": 1100, "height": 360}, "fps": 60,
                "setup": {"modules": ["music", "activities", "systemhud", "unlock"],
                          "pages": [["music"], ["activities"]]}, "steps": steps}
    return scenario, switches, blocks


def compare_to_reference(name):
    """Images de chaque série aux mêmes instants que la référence (série 0), et écart avec elle."""
    folder = os.path.join(OUT, name)
    video = os.path.join(folder, "notch.mp4")
    times = actual_times(folder)
    blocks = json.load(open(os.path.join(folder, "blocks.json")))
    switches = json.load(open(os.path.join(folder, "switches.json")))
    # Instants où l'état doit être stable : fin d'ouverture, page 2, replié, bulle, retour, volume, coche
    probes = [1.0, 2.2, 3.3, 4.4, 5.3, 6.4, 9.2, 10.6]
    grabs = {}
    for b, start in enumerate(blocks):
        base = times.get(round(start, 2), start)
        for k, offset in enumerate(probes):
            png = os.path.join(folder, f"p{b}-{k}.png")
            subprocess.run(["ffmpeg", "-v", "error", "-y", "-ss", str(base + offset), "-i", video, "-frames:v", "1",
                            "-vf", "crop=1300:440:450:0,scale=325:-1,format=gray", "-f", "rawvideo", png + ".raw"], check=True)
            subprocess.run(["ffmpeg", "-v", "error", "-y", "-ss", str(base + offset), "-i", video, "-frames:v", "1",
                            "-vf", "crop=1300:440:450:0,scale=325:-1", png], check=True)
            grabs[(b, k)] = (png, open(png + ".raw", "rb").read())
    labels = ["ouverte", "page 2", "repliée", "bulle", "bulle rentrée", "volume", "coche Face ID", "fin"]
    print(name)
    cells = []
    for b, start in enumerate(blocks):
        during = [round(s["at"] - start, 2) for s in switches if start <= s["at"] < start + ANIMATION_BLOCK]
        gaps = []
        for k in range(len(probes)):
            ref, cur = grabs[(0, k)][1], grabs[(b, k)][1]
            gaps.append(round(sum(abs(x - y) for x, y in zip(ref, cur)) / len(ref), 1))
            cells.append((grabs[(b, k)][0], f"{b} {labels[k]} {gaps[-1]}"))
        print(f"  série {b} bureau à +{during} s : écarts {dict(zip(labels, gaps))}")
    subprocess.run([os.path.join(OUT, "contact-sheet"), os.path.join(folder, "planche.png"), str(len(probes)), "300",
                    *[a for c in cells for a in c]], check=True)


def animations_test():
    steps = [{"at": 0.5, "do": "music.play", "title": "danker", "artist": "Gabester"},
             {"at": 0.8, "do": "timer.start", "minutes": 25}]
    switches, blocks = [], []
    t = 4.0
    for before in ANIMATION_SWITCHES:
        t += max((s[1] for s in before), default=0) if before else 0
        for direction, ahead in before or []:
            switches.append((round(t - ahead, 2), direction))
        for offset, action, params, _, _ in ANIMATION_SET:
            steps.append(dict(params, at=round(t + offset, 2), **{"do": action}))
        blocks.append(round(t, 2))
        t += ANIMATION_BLOCK
    steps.append({"at": round(t, 2), "do": "end"})
    switches.sort()
    scenario = {"duration": round(t + 0.5, 2), "region": {"width": 1100, "height": 360}, "fps": 60,
                "setup": {"modules": ["music", "activities", "systemhud", "unlock"],
                          "pages": [["music"], ["activities"]]}, "steps": steps}
    return scenario, switches, blocks


def analyze_animations(name="animations"):
    folder = os.path.join(OUT, name)
    video = os.path.join(folder, "notch.mp4")
    times = actual_times(folder)
    blocks = json.load(open(os.path.join(folder, "blocks.json")))
    switches = json.load(open(os.path.join(folder, "switches.json")))
    rows, cells = [], []
    for b, start in enumerate(blocks):
        row = {"serie": b, "debut": start,
               "bureaux_avant": [s["at"] for s in switches if start - 4 < s["at"] < start]}
        for offset, _, _, label, length in ANIMATION_SET:
            at = times.get(round(start + offset, 2), start + offset)
            diffs = frame_diffs(video, at - 0.05, length)
            m = motion_report(diffs)
            row[label] = {"images": m["frames"], "saccades": len(m["stalls"]), "saut": m["jump"],
                          "mouvement": round(sum(diffs), 1)}
        rows.append(row)
        # Planche : chaque série sur une rangée, mêmes instants (ouverture, page, bulle, volume, Face ID)
        for k, offset in enumerate([0.15, 0.3, 1.5, 3.0, 3.8, 5.6, 7.9, 8.6]):
            png = os.path.join(folder, f"s{b}-{k}.png")
            at = times.get(round(start, 2), start) + offset
            subprocess.run(["ffmpeg", "-v", "error", "-y", "-ss", str(at), "-i", video, "-frames:v", "1",
                            "-vf", "crop=1300:440:450:0,scale=650:-1", png], check=True)
            cells.append((png, f"série {b} +{offset}s"))
    json.dump(rows, open(os.path.join(folder, "report.json"), "w"), indent=1)
    sheet_tool = os.path.join(OUT, "contact-sheet")
    subprocess.run([sheet_tool, os.path.join(folder, "planche.png"), "8", "330", *[a for c in cells for a in c]], check=True)
    for row in rows:
        print(f"série {row['serie']} (bureaux avant : {row['bureaux_avant']})")
        for _, _, _, label, _ in ANIMATION_SET:
            print(f"   {label:13} {row[label]}")


def gray_frames(video, crop, fps, size):
    """Images en niveaux de gris (octets), recadrées puis réduites à `size` (largeur, hauteur)."""
    w, h = size
    proc = subprocess.Popen(["ffmpeg", "-v", "error", "-i", video, "-vf", f"crop={crop},fps={fps},scale={w}:{h},format=gray",
                             "-f", "rawvideo", "-"], stdout=subprocess.PIPE)
    while True:
        frame = proc.stdout.read(w * h)
        if len(frame) < w * h:
            break
        yield frame


def analyze_spaces():
    folder = os.path.join(OUT, "spaces")
    video = os.path.join(folder, "notch.mp4")
    switches = json.load(open(os.path.join(folder, "switches.json")))
    # 1. Barres de l'égaliseur (côté droit de l'encoche repliée) : écart entre images successives.
    #    Zone filmée de 1100 pt (2200 px) centrée sur l'encoche de 220 pt : barres entre +110 et +148 pt.
    previous, diffs = None, []
    for frame in gray_frames(video, "84:68:1316:4", 60, (42, 34)):
        if previous is not None:
            diffs.append(sum(abs(a - b) for a, b in zip(frame, previous)) / len(frame))
        previous = frame
    frozen, start = [], None
    for i, d in enumerate(diffs + [99]):
        if d < 0.05 and start is None:
            start = i
        elif d >= 0.05 and start is not None:
            if i - start >= 30:  # au moins 0,5 s sans le moindre mouvement
                frozen.append((round(start / 60, 2), round(i / 60, 2)))
            start = None
    # 2. Encoche : cadre des pixels noirs (taille et position) dix fois par seconde.
    boxes = []
    for frame in gray_frames(video, "2200:720:0:0", 10, (550, 180)):
        xs = [i % 550 for i in range(len(frame)) if frame[i] < 30]
        ys = [i // 550 for i in range(len(frame)) if frame[i] < 30]
        boxes.append((min(xs), max(xs), max(ys)) if xs else None)
    changes = []
    for i in range(1, len(boxes)):
        if boxes[i] != boxes[i - 1]:
            changes.append({"t": round(i / 10, 1), "box": boxes[i]})
    report = {"switches": switches, "frozenBars": frozen, "notchChanges": changes,
              "barDiffsPerSecond": [round(sum(diffs[s:s + 60]) / 60, 2) for s in range(0, len(diffs), 60)]}
    json.dump(report, open(os.path.join(folder, "report.json"), "w"), indent=1)
    print("Changements de bureau :", [s["at"] for s in switches])
    print("Barres figées (début, fin en s) :", frozen)
    print("Mouvement des barres par seconde :", report["barDiffsPerSecond"])
    print("Changements du cadre de l'encoche :", len(changes))
    for c in changes[:60]:
        print("  ", c)


if __name__ == "__main__":
    args = sys.argv[1:]
    only = None
    if "--only" in args:
        i = args.index("--only")
        only = args[i + 1].split(",")
        del args[i:i + 2]
    command = args[0] if args else "scenarios"
    names = args[1:] or list(NOTCHES)
    if command == "scenarios":
        write_scenarios(only)
    elif command == "glass":
        # Fond « Verre » : le verre dépend de ce qu'il y a derrière l'encoche, que l'enregistrement de la
        # fenêtre ne montre pas. Une vraie capture macOS par combinaison, assemblées en planches.
        os.environ.setdefault("NOTCHKIT_SHOT_RECT", "480,0,840,260")
        data, marks = scenario("auto", only, glass=True)
        record_spaces("verre", data, [], shots=[m["still"] for m in marks], music=False)
        folder = os.path.join(OUT, "verre")
        json.dump(marks, open(os.path.join(folder, "marks.json"), "w"), indent=1)
        sheet_tool = os.path.join(OUT, "contact-sheet")
        subprocess.run(["swiftc", "-O", os.path.join(ROOT, "scripts", "contact-sheet.swift"), "-o", sheet_tool], check=True)
        cells = [(os.path.join(folder, f"shot-{m['still']:05.1f}.png"), m["label"]) for m in marks]
        cells = [c for c in cells if os.path.exists(c[0])]
        for n in range(0, len(cells), 16):
            args = [a for cell in cells[n:n + 16] for a in cell]
            subprocess.run([sheet_tool, os.path.join(folder, f"planche-{n // 16 + 1}.png"), "4", "620", *args], check=True)
        print(f"verre : {len(cells)} captures, planches dans {folder}")
    elif command == "record":
        write_scenarios(only)
        record(names)
    elif command == "analyze":
        analyze(names)
    elif command == "spaces":
        record_spaces()
        analyze_spaces()
    elif command == "spaces-analyze":
        analyze_spaces()
    elif command == "animations":
        scenario, switches, blocks = animations_test()
        record_spaces("animations", scenario, switches)
        json.dump(blocks, open(os.path.join(OUT, "animations", "blocks.json"), "w"))
        analyze_animations()
    elif command == "animations-analyze":
        analyze_animations()
    elif command == "faceid":
        # Face ID seul : référence, puis après des changements de bureau, et pendant
        steps = [{"at": a, "do": "unlock"} for a in (3, 10, 17, 24, 31, 38)] + [{"at": 44, "do": "end"}]
        scenario = {"duration": 45, "region": {"width": 1100, "height": 360}, "fps": 60,
                    "setup": {"modules": ["unlock"], "pages": [["clock"]]}, "steps": steps}
        # Nom du dossier en argument (ex. « faceid-apres ») pour garder plusieurs prises
        name = next((n for n in names if n.startswith("faceid")), "faceid")
        record_spaces(name, scenario, [(7.5, "right"), (14.5, "left"), (24.6, "right"), (31.9, "left")],
                      shots=[a + 1.9 for a in (3, 10, 17, 24, 31, 38)])
        folder = os.path.join(OUT, name)
        print(open(os.path.join(folder, "diag.log")).read())
        unlocks = [s["at"] for s in json.load(open(os.path.join(folder, "timeline.json")))["steps"] if s["do"] == "unlock"]
        rows = []
        for i, at in enumerate(unlocks):
            row = os.path.join(folder, f"r{i}.png")
            subprocess.run(["ffmpeg", "-v", "error", "-y", "-ss", str(at + 0.9), "-i", os.path.join(folder, "notch.mp4"), "-t", "2.2",
                            "-vf", "fps=5,crop=300:300:950:0,scale=90:-1,tile=11x1", "-update", "1", row], check=True)
            rows += ["-i", row]
        subprocess.run(["ffmpeg", "-v", "error", "-y", *rows, "-filter_complex", f"vstack={len(unlocks)}",
                        os.path.join(folder, "all.png")], check=True)
    elif command == "faceid-manuel":
        # Face ID toutes les 5 s pendant une minute ; c'est le propriétaire qui change de bureau
        # (balayage au trackpad) pendant certaines animations. Vraies captures d'écran à +1,9 s.
        times = [3 + 5 * i for i in range(12)]
        steps = [{"at": a, "do": "unlock"} for a in times] + [{"at": 63, "do": "end"}]
        scenario = {"duration": 64, "region": {"width": 1100, "height": 360}, "fps": 60,
                    "setup": {"modules": ["unlock"], "pages": [["clock"]]}, "steps": steps}
        record_spaces("faceid-manuel", scenario, [], shots=[a + 1.9 for a in times], music=False)
        folder = os.path.join(OUT, "faceid-manuel")
        print(open(os.path.join(folder, "diag.log")).read())
        unlocks = [s["at"] for s in json.load(open(os.path.join(folder, "timeline.json")))["steps"] if s["do"] == "unlock"]
        rows = []
        for i, at in enumerate(unlocks):
            row = os.path.join(folder, f"r{i}.png")
            subprocess.run(["ffmpeg", "-v", "error", "-y", "-ss", str(at + 0.3), "-i", os.path.join(folder, "notch.mp4"), "-t", "3.0",
                            "-vf", "fps=5,crop=300:300:950:0,scale=90:-1,tile=15x1", "-update", "1", row], check=True)
            rows += ["-i", row]
        subprocess.run(["ffmpeg", "-v", "error", "-y", *rows, "-filter_complex", f"vstack={len(unlocks)}",
                        os.path.join(folder, "all.png")], check=True)
    elif command == "during":
        scenario, switches, blocks = during_test()
        name = next((n for n in names if n.startswith("pendant")), "pendant")
        record_spaces(name, scenario, switches)
        json.dump(blocks, open(os.path.join(OUT, name, "blocks.json"), "w"))
        compare_to_reference(name)
    else:
        sys.exit(__doc__)
