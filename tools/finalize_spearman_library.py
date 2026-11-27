"""Update review instructions and viewport framing without changing animation data."""
import bpy, json
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'build/spearman_attacks_10'
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'art/spearman_attacks_10.blend'))
manifest=json.loads((OUT/'animation_manifest.json').read_text(encoding='utf-8'))
notes='''КОПЕЙЩИК — 10 ВАРИАНТОВ УДАРА

Пробел — проиграть всю последовательность. 30 кадров/с.
01 и 06: в щит. 02–05, 07–08 и 10: в открытые зоны.
09: первый укол в щит, второй под щит в колено.
10: финт в голову с остановкой перед целью, отведение и укол в голень.

Дополнительно: боевая стойка с дыханием, вход и выход из стойки.
Все удары начинаются и заканчиваются в общей стойке.
Копьё закреплено в кисти; ноги сохраняют опору. В выпаде и ответном
уколе шаг возвращается на исходное место. Растяжения костей нет.

В коллекции REFERENCE OPPONENT находится неподвижный противник для
проверки дистанции, щита и открытых точек. Коллекцию можно скрыть.
Проверены все кадры: нет нежелательных пересечений своего и чужого щита;
намеренные контакты наконечника отклоняются от цели менее чем на 3 мм.

Для редактирования отдельного клипа отключите дорожку REVIEW в NLA,
затем выберите нужный Action в Action Editor. Метки CONTACT указывают
кадры контактов; цели также записаны в свойствах Action и JSON.

Экспорт spearman_attacks_10.glb: основной воин и 13 анимаций.
Оружие подключается к GripRight / GripLeft; исходные отдельные модели
находятся в assets/spear.glb и assets/shield.glb. Противник в экспорт не входит.
Подбор ударов и события урона в игре подключаются отдельно.

КЛИПЫ
'''
for name,entry in manifest['clips'].items():
    impacts=', '.join(str(f) for f in entry['impact_frames']) or '—'
    notes+=f'{name}\n  {entry["label"]}; {entry["duration"]:.2f} с; контакт: {impacts}\n'
(OUT/'README.txt').write_text(notes,encoding='utf-8')
text=bpy.data.texts.get('READ ME - SPEAR LIBRARY');text.clear();text.write(notes)
scene=bpy.context.scene
scene.camera.rotation_euler=(Vector((0,-.86,1.05))-scene.camera.location).to_track_quat('-Z','Y').to_euler()
scene.render.resolution_x=960;scene.render.resolution_y=720
scene.frame_set(1)
if bpy.context.screen:
    for area in bpy.context.screen.areas:
        if area.type=='NLA_EDITOR':
            region=next((r for r in area.regions if r.type=='WINDOW'),None)
            if region:
                try:
                    with bpy.context.temp_override(area=area,region=region):bpy.ops.nla.view_all()
                except RuntimeError:pass
        elif area.type=='VIEW_3D':
            area.spaces.active.region_3d.view_perspective='CAMERA'
            area.spaces.active.overlay.show_overlays=False
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'art/spearman_attacks_10.blend'))
print('FINAL_LIBRARY_SAVED',flush=True)
