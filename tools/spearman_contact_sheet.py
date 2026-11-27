"""Assemble the ten unmodified Blender contact renders for visual review."""
import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'build/spearman_attacks_10'
manifest=json.loads((OUT/'animation_manifest.json').read_text(encoding='utf-8'))
font=ImageFont.truetype('C:/Windows/Fonts/arial.ttf',20)
small=ImageFont.truetype('C:/Windows/Fonts/arial.ttf',16)
title=ImageFont.truetype('C:/Windows/Fonts/arialbd.ttf',33)
sheet=Image.new('RGB',(1800,800),(22,29,36));draw=ImageDraw.Draw(sheet)
draw.text((28,20),'КОПЕЙЩИК  /  10 ВАРИАНТОВ УДАРА',font=title,fill=(240,237,225))
draw.text((28,62),'Общая стойка • подготовка • контакт • возврат    |    Blender / 30 fps',font=small,fill=(168,184,196))
entries=[(n,e) for n,e in manifest['clips'].items() if e['kind']=='attack']
captions=json.loads((OUT/'preview_captions.json').read_text(encoding='utf-8'))
starts={c['action']:round(c['start']*30) for c in captions}
for i,(name,entry) in enumerate(entries):
    x=(i%5)*360;y=104+(i//5)*340
    path=OUT/'frames'/('frame_%04d.png'%(starts[name]+entry['impact_frames'][-1]))
    image=Image.open(path).convert('RGB').resize((360,270),Image.Resampling.LANCZOS)
    sheet.paste(image,(x,y))
    draw.text((x+13,y+275),f'{i+1:02d}  '+entry['label'],font=font,fill=(237,235,221))
    contacts=' / '.join(str(f) for f in entry['impact_frames'])
    draw.text((x+13,y+302),f'{entry["duration"]:.2f} с  ·  контакт: {contacts} кадр',font=small,fill=(152,174,191))
sheet.save(OUT/'contact_sheet.jpg',quality=93)
print(OUT/'contact_sheet.jpg')
