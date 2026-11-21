#!/usr/bin/env python3
"""Build a tiny Lastbook data folder for testing Lastbook Remote against a real share listener.

    python3 scripts/make_sample_library.py /tmp/lastbook-sample
    cd /path/to/lastbook   # the share-with-devices branch (Lastbook PR #343)
    python3 server.py --lan --no-index --data /tmp/lastbook-sample

It writes library-data/ (catalog.json, summary.json, search.sqlite, documents, pages, videos) and derived/.
Videos need ffmpeg: one H.264 MP4 (plays everywhere) and one AV1 MP4 (to see the "can't play" message).
Nothing here is real library content.
"""
import json, shutil, sqlite3, subprocess, sys
from pathlib import Path


def pdf_bytes(pages):
    """A small valid PDF with one line of Helvetica text per page."""
    objs = []
    n = len(pages)
    kids = ' '.join(f'{3 + i * 2} 0 R' for i in range(n))
    objs.append('<< /Type /Catalog /Pages 2 0 R >>')
    objs.append(f'<< /Type /Pages /Kids [{kids}] /Count {n} >>')
    font_obj = 3 + n * 2
    for i, text in enumerate(pages):
        page_no, content_no = 3 + i * 2, 4 + i * 2
        objs.append(f'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 {font_obj} 0 R >> >> /Contents {content_no} 0 R >>')
        safe = text.replace('\\', '\\\\').replace('(', '\\(').replace(')', '\\)')
        stream = f'BT /F1 24 Tf 72 700 Td ({safe}) Tj ET'
        objs.append(f'<< /Length {len(stream)} >>\nstream\n{stream}\nendstream')
    objs.append('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>')
    out = bytearray(b'%PDF-1.4\n')
    offsets = []
    for i, o in enumerate(objs, 1):
        offsets.append(len(out))
        out += f'{i} 0 obj\n{o}\nendobj\n'.encode('latin-1')
    xref = len(out)
    out += f'xref\n0 {len(objs) + 1}\n0000000000 65535 f \n'.encode()
    for off in offsets:
        out += f'{off:010d} 00000 n \n'.encode()
    out += f'trailer\n<< /Size {len(objs) + 1} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n'.encode()
    return bytes(out)


def video(path, codec):
    if not shutil.which('ffmpeg'):
        return False
    args = {'h264': ['-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-profile:v', 'main'],
            'av1': ['-c:v', 'libsvtav1', '-pix_fmt', 'yuv420p']}[codec]
    cmd = ['ffmpeg', '-v', 'error', '-y', '-f', 'lavfi', '-i', 'testsrc2=size=640x360:rate=25:duration=20',
           '-f', 'lavfi', '-i', 'sine=frequency=440:duration=20', *args, '-c:a', 'aac', '-shortest',
           '-movflags', '+faststart', str(path)]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        print(f'ffmpeg failed for {path.name}: {r.stderr.strip()[-300:]}', file=sys.stderr)
    return r.returncode == 0


def main():
    root = Path(sys.argv[1] if len(sys.argv) > 1 else '/tmp/lastbook-sample').resolve()
    lib = root / 'library-data'
    for d in ('documents', 'pages', 'videos', 'collections', 'courses'):
        (lib / d).mkdir(parents=True, exist_ok=True)
    (root / 'derived').mkdir(parents=True, exist_ok=True)

    (lib / 'documents' / 'water-guide.pdf').write_bytes(pdf_bytes([
        'Boil water for one minute to make it safe.', 'Store treated water in clean covered containers.', 'Page three: chlorine dosing.']))
    (lib / 'courses' / 'circuits-notes.pdf').write_bytes(pdf_bytes(['Lecture 1: Ohm law V = I R', 'Lecture 2: Kirchhoff laws']))
    (lib / 'documents' / 'first-aid.txt').write_text('First aid basics\n\nPress firmly on a bleeding wound.\n', encoding='utf-8')
    (lib / 'documents' / 'notes.md').write_text('# Solar notes\n\n- Panels face south\n- Check the charge controller\n', encoding='utf-8')
    (lib / 'pages' / 'knots.html').write_text('<!doctype html><title>Knots</title><h1>Knots</h1><p>The bowline makes a fixed loop.</p>', encoding='utf-8')

    recs = [
        dict(id='water-guide', kind='pdf', path='documents/water-guide.pdf', title='Safe Drinking Water Guide', category='water-treatment', collection='Water Basics', publisher='CDC', pages=3),
        dict(id='first-aid-txt', kind='text', path='documents/first-aid.txt', title='First aid basics', category='first-aid', collection='First Aid', publisher='Red Cross'),
        dict(id='solar-md', kind='text', path='documents/notes.md', title='Solar notes', category='offgrid-power', collection='Power', publisher='Community'),
        dict(id='knots-page', kind='html', path='pages/knots.html', title='Knots', category='knots', collection='Outdoors', publisher='Community'),
        dict(id='circuits-notes', kind='pdf', path='courses/circuits-notes.pdf', title='Circuits lecture notes', category='circuits', collection='MIT 6.002 Circuits', publisher='MIT OpenCourseWare', course='6.002', pages=2),
    ]
    if video(lib / 'videos' / 'h264-sample.mp4', 'h264'):
        recs.append(dict(id='vid-h264', kind='video', path='videos/h264-sample.mp4', title='Test pattern (H.264)', category='circuits', collection='MIT 6.002 Circuits', publisher='MIT OpenCourseWare', course='6.002', duration=20))
    if video(lib / 'videos' / 'av1-sample.mp4', 'av1'):
        recs.append(dict(id='vid-av1', kind='video', path='videos/av1-sample.mp4', title='Test pattern (AV1)', category='first-aid', collection='First Aid', publisher='Red Cross', duration=20))
    for r in recs:
        r['bytes'] = (lib / r['path']).stat().st_size
    (lib / 'catalog.json').write_text(json.dumps(recs, indent=1), encoding='utf-8')
    (lib / 'summary.json').write_text(json.dumps({'resources': len(recs), 'pdfs': 2, 'videos': sum(r['kind'] == 'video' for r in recs), 'collections': 5}), encoding='utf-8')

    db = lib / 'search.sqlite'
    if db.exists():
        db.unlink()
    con = sqlite3.connect(db)
    con.execute('CREATE VIRTUAL TABLE pages USING fts5(doc_id UNINDEXED,title,collection,category,path UNINDEXED,page UNINDEXED,body,tokenize="unicode61")')
    rows = [('water-guide', 1, 'Boil water for one minute to make it safe.'), ('water-guide', 2, 'Store treated water in clean covered containers.'),
            ('water-guide', 3, 'Chlorine dosing.'), ('first-aid-txt', 1, 'Press firmly on a bleeding wound.'),
            ('solar-md', 1, 'Panels face south. Check the charge controller.'), ('knots-page', 1, 'The bowline makes a fixed loop.'),
            ('circuits-notes', 1, 'Ohm law voltage current resistance'), ('circuits-notes', 2, 'Kirchhoff laws')]
    by = {r['id']: r for r in recs}
    for doc, page, body in rows:
        r = by[doc]
        con.execute('INSERT INTO pages VALUES (?,?,?,?,?,?,?)', (doc, r['title'], r['collection'], r['category'], r['path'], page, body))
    con.commit()
    con.close()
    print(root)


if __name__ == '__main__':
    main()
