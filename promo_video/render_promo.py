# -*- coding: utf-8 -*-
"""
ALFA SOFT ERP -- High-End Promotional Commercial Video Generator
Generates a 1080p 30fps Full HD commercial with synced Arabic voiceover and animations.
"""

import os
import math
import subprocess
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import imageio_ffmpeg
import arabic_reshaper
from bidi.algorithm import get_display

# --- Typography & Arabic Reshaping Helpers ---
FONT_REGULAR_PATH = r"C:\Windows\Fonts\segoeui.ttf"
FONT_BOLD_PATH = r"C:\Windows\Fonts\segoeuib.ttf"
FONT_ARABIC_BOLD = r"C:\Windows\Fonts\arialbd.ttf"
FONT_ARABIC_REG = r"C:\Windows\Fonts\arial.ttf"

def render_arabic_text(text: str) -> str:
    """Reshape and reorder Arabic text for correct RTL rendering."""
    if not text:
        return ""
    reshaped = arabic_reshaper.reshape(text)
    return get_display(reshaped)

def get_font(path: str, size: int):
    try:
        return ImageFont.truetype(path, size)
    except Exception:
        return ImageFont.truetype(FONT_ARABIC_REG, size)

# --- Geometry & Smoothing Helpers ---
def smoothstep(edge0, edge1, x):
    x = max(0.0, min(1.0, (x - edge0) / (edge1 - edge0)))
    return x * x * (3 - 2 * x)

def ease_out_back(x: float) -> float:
    c1 = 1.70158
    c3 = c1 + 1
    x = max(0.0, min(1.0, x))
    return 1 + c3 * math.pow(x - 1, 3) + c1 * math.pow(x - 1, 2)

# --- Particle System for Ambient Background ---
class ParticleSystem:
    def __init__(self, count=60, width=1920, height=1080):
        np.random.seed(42)
        self.count = count
        self.width = width
        self.height = height
        self.x = np.random.uniform(0, width, count)
        self.y = np.random.uniform(0, height, count)
        self.vx = np.random.uniform(-0.6, 0.6, count)
        self.vy = np.random.uniform(-0.8, -0.2, count)
        self.radii = np.random.uniform(2, 5, count)
        self.alpha = np.random.uniform(60, 180, count)

    def update(self):
        self.x += self.vx
        self.y += self.vy
        self.x %= self.width
        self.y %= self.height

    def draw(self, draw: ImageDraw.Draw):
        for i in range(self.count):
            r = self.radii[i]
            x, y = self.x[i], self.y[i]
            a = int(self.alpha[i])
            # Draw particle with cyan/blue glow
            draw.ellipse([x - r, y - r, x + r, y + r], fill=(0, 229, 255, a))

# --- Main Video Renderer ---
def render_promo_video():
    width, height = 1920, 1080
    fps = 30
    duration_sec = 34.0
    total_frames = int(fps * duration_sec)

    ffmpeg_exe = imageio_ffmpeg.get_ffmpeg_exe()
    audio_path = "promo_video/master_audio.mp3"
    output_video_path = "promo_video/alfa_soft_promo.mp4"

    if not os.path.exists(audio_path):
        raise FileNotFoundError(f"Audio file missing: {audio_path}")

    # Load Assets
    icon_path = r"assets\icons\app_icon_1024.png"
    pos_shot_path = r"C:\Users\MAX\.gemini\antigravity\brain\f24881af-6105-4531-bcc6-4f754483d3ec\.user_uploaded\media_1794835173216_3dca017d.jpg"
    license_shot_path = r"C:\Users\MAX\.gemini\antigravity\brain\f24881af-6105-4531-bcc6-4f754483d3ec\.user_uploaded\media_1794832899776_138bab7a.png"
    catalog_shot_path = r"C:\Users\MAX\.gemini\antigravity\brain\f24881af-6105-4531-bcc6-4f754483d3ec\.user_uploaded\media_1794844293311_9693bb51.png"

    app_icon = Image.open(icon_path).convert("RGBA") if os.path.exists(icon_path) else Image.new("RGBA", (256, 256), (0, 150, 255, 255))
    pos_shot = Image.open(pos_shot_path).convert("RGBA") if os.path.exists(pos_shot_path) else None
    license_shot = Image.open(license_shot_path).convert("RGBA") if os.path.exists(license_shot_path) else None
    catalog_shot = Image.open(catalog_shot_path).convert("RGBA") if os.path.exists(catalog_shot_path) else None

    # Pre-render deep gradient background (1920x1080)
    base_bg = Image.new("RGBA", (width, height))
    bg_draw = ImageDraw.Draw(base_bg)
    # Radial dark navy-blue gradient
    for y in range(height):
        ratio = y / height
        r = int(7 + ratio * 8)
        g = int(14 + ratio * 15)
        b = int(28 + ratio * 35)
        bg_draw.line([(0, y), (width, y)], fill=(r, g, b, 255))

    particles = ParticleSystem(count=70, width=width, height=height)

    # Subtitles timeline definition
    # 0.1 - 7.1s: عندما تلتقي السرعة الخارقة بإدارة الأعمال الذكية، تظهر منظومة ألفا سوفت.
    # 7.1 - 15.4s: كاشير بيع فائق السرعة، تعدد في العملات، وفواتير فورية متوافقة مع أعتى ضغوط العمل.
    # 15.4 - 26.6s: مستودعات دقيقة ومترابطة، أمان مشفر ببصمة العتاد، ومزامنة شبكية تعمل بكفاءة تامة دون الحاجة للإنترنت.
    # 26.6 - 34.0s: ألفا سوفت، سيطرة مطلقة على تجارتك. ارتقِ بأعمالك الآن.
    subtitles = [
        (0.0, 7.2, "عندما تلتقي السرعة الخارقة بإدارة الأعمال الذكية، تظهر منظومة ألفا سوفت"),
        (7.2, 15.4, "كاشير بيع فائق السرعة، تعدد في العملات، وفواتير فورية متوافقة مع أعتى ضغوط العمل"),
        (15.4, 26.6, "مستودعات دقيقة ومترابطة، أمان مشفر ببصمة العتاد، ومزامنة شبكية تعمل بكفاءة دون إنترنت"),
        (26.6, 34.0, "ألفا سوفت، سيطرة مطلقة على تجارتك. ارتقِ بأعمالك الآن"),
    ]

    # Fonts
    font_brand = get_font(FONT_BOLD_PATH, 58)
    font_title = get_font(FONT_ARABIC_BOLD, 46)
    font_subtitle = get_font(FONT_ARABIC_BOLD, 30)
    font_card_title = get_font(FONT_ARABIC_BOLD, 28)
    font_card_body = get_font(FONT_ARABIC_REG, 22)
    font_ticker = get_font(FONT_ARABIC_BOLD, 26)
    font_badge = get_font(FONT_ARABIC_BOLD, 22)

    # Setup FFmpeg rawvideo pipe
    ffmpeg_cmd = [
        ffmpeg_exe, "-y",
        "-f", "rawvideo",
        "-vcodec", "rawvideo",
        "-s", f"{width}x{height}",
        "-pix_fmt", "rgb24",
        "-r", str(fps),
        "-i", "-",  # Video from stdin pipe
        "-i", audio_path,  # Audio from master mix
        "-c:v", "libx264",
        "-preset", "medium",
        "-crf", "19",
        "-c:a", "aac",
        "-b:a", "192k",
        "-pix_fmt", "yuv420p",
        "-shortest",
        output_video_path
    ]

    print(f"Starting Video Render: {width}x{height} @ {fps}fps, total frames: {total_frames}...")
    proc = subprocess.Popen(ffmpeg_cmd, stdin=subprocess.PIPE, stderr=subprocess.PIPE)

    try:
        for f in range(total_frames):
            time_sec = f / fps
            particles.update()

            # Create frame from base background
            frame = base_bg.copy()
            draw = ImageDraw.Draw(frame)

            # Draw ambient particles
            particles.draw(draw)

            # Top branding header bar
            draw.rectangle([0, 0, width, 65], fill=(10, 18, 36, 220))
            draw.line([(0, 65), (width, 65)], fill=(0, 229, 255, 120), width=2)
            
            # Header text
            header_brand = "ALFA SOFT ERP"
            draw.text((60, 16), header_brand, font=get_font(FONT_BOLD_PATH, 26), fill=(0, 229, 255, 255))
            
            sys_type = render_arabic_text("نظام تخطيط وإدارة الموارد والمنشآت التجارية")
            draw.text((width - 480, 18), sys_type, font=get_font(FONT_ARABIC_BOLD, 18), fill=(203, 213, 225, 230))

            # ------------------------------------------------------------------
            # SCENE 1: Introduction & High-End 3D Brand Logo (0.0s - 7.2s)
            # ------------------------------------------------------------------
            if time_sec < 7.2:
                scene_progress = time_sec / 7.2
                logo_scale = 0.85 + 0.15 * math.sin(scene_progress * math.pi)
                icon_size = int(320 * logo_scale)
                icon_resized = app_icon.resize((icon_size, icon_size), Image.Resampling.LANCZOS)

                cx, cy = width // 2, 420
                # Glowing back-circles
                glow_r = int(icon_size * 0.7)
                draw.ellipse([cx - glow_r, cy - glow_r, cx + glow_r, cy + glow_r], fill=(0, 150, 255, 35))
                draw.ellipse([cx - int(glow_r*0.7), cy - int(glow_r*0.7), cx + int(glow_r*0.7), cy + int(glow_r*0.7)], fill=(0, 229, 255, 55))

                # Paste icon centered
                frame.alpha_composite(icon_resized, (cx - icon_size // 2, cy - icon_size // 2))

                # Luminous Brand Title
                brand_title = "ALFA SOFT"
                draw.text((cx - 160, 640), brand_title, font=font_brand, fill=(255, 255, 255, 255))
                
                tagline = render_arabic_text("السرعة الخارقة • الإدارة الذكية المتكاملة")
                draw.text((cx - 240, 730), tagline, font=font_subtitle, fill=(0, 229, 255, 255))

                # Floating glass badges
                b1 = render_arabic_text("⚡ أداء فائق السرعة")
                b2 = render_arabic_text("🔒 تشفير عتادي متطور")
                b3 = render_arabic_text("💎 تصميم عصري زجاجي")

                badge_y = 820
                # 3 Pill Badges
                for bx, text_badge in [(cx - 420, b1), (cx - 120, b2), (cx + 180, b3)]:
                    draw.rounded_rectangle([bx, badge_y, bx + 240, badge_y + 50], radius=25, fill=(15, 23, 42, 210), outline=(0, 229, 255, 140), width=2)
                    draw.text((bx + 25, badge_y + 10), text_badge, font=font_badge, fill=(241, 245, 249, 255))

            # ------------------------------------------------------------------
            # SCENE 2: POS, Fast Cashier, Multi-Currency (7.2s - 15.4s)
            # ------------------------------------------------------------------
            elif 7.2 <= time_sec < 15.4:
                scene_time = time_sec - 7.2
                t_in = smoothstep(0, 1.2, scene_time)

                # Show POS Screen Shot with subtle Ken Burns zoom
                if pos_shot:
                    zoom = 1.0 + 0.08 * (scene_time / 8.2)
                    target_w = int(1080 * zoom)
                    target_h = int(680 * zoom)
                    shot_resized = pos_shot.resize((target_w, target_h), Image.Resampling.LANCZOS)
                    # Crop to fixed container 1080x680
                    x_crop = (target_w - 1080) // 2
                    y_crop = (target_h - 680) // 2
                    shot_cropped = shot_resized.crop((x_crop, y_crop, x_crop + 1080, y_crop + 680))

                    # Position with slide-in
                    pos_x = int(-200 + 300 * t_in)
                    pos_y = 150

                    # Draw drop shadow & container
                    draw.rounded_rectangle([pos_x - 10, pos_y - 10, pos_x + 1090, pos_y + 690], radius=16, fill=(0, 0, 0, 180))
                    frame.alpha_composite(shot_cropped, (pos_x, pos_y))
                    draw.rounded_rectangle([pos_x, pos_y, pos_x + 1080, pos_y + 680], radius=16, outline=(0, 229, 255, 180), width=3)

                # Side Glass Cards (Right side)
                card_x = int(width + 400 - 660 * t_in)
                
                # Card 1: Fast Cashier
                c1_y = 180
                draw.rounded_rectangle([card_x, c1_y, card_x + 580, c1_y + 240], radius=18, fill=(13, 23, 44, 235), outline=(0, 229, 255, 180), width=2)
                t1 = render_arabic_text("⚡ شاشة الكاشير السريع (POS)")
                draw.text((card_x + 35, c1_y + 25), t1, font=font_card_title, fill=(0, 229, 255, 255))
                
                lines1 = [
                    "• إتمام الفواتير بلمح البصر بزر F10",
                    "• باركود ذكي وبحث لحظي فوري",
                    "• طباعة حرارية فورية 80mm و A4"
                ]
                for i, l in enumerate(lines1):
                    draw.text((card_x + 40, c1_y + 80 + i * 45), render_arabic_text(l), font=font_card_body, fill=(241, 245, 249, 255))

                # Card 2: Multi-Currency
                c2_y = 460
                draw.rounded_rectangle([card_x, c2_y, card_x + 580, c2_y + 260], radius=18, fill=(13, 23, 44, 235), outline=(245, 158, 11, 180), width=2)
                t2 = render_arabic_text("💰 تعدد العملات والأسعار الذكية")
                draw.text((card_x + 35, c2_y + 25), t2, font=font_card_title, fill=(251, 191, 36, 255))
                
                lines2 = [
                    "• ريال يمني (YER) • ريال سعودي (SAR) • دولار (USD)",
                    "• تسعير جملة وتجزئة فوري ودقيق",
                    "• حساب فروق الصرف والأرباح آلياً"
                ]
                for i, l in enumerate(lines2):
                    draw.text((card_x + 40, c2_y + 80 + i * 45), render_arabic_text(l), font=font_card_body, fill=(241, 245, 249, 255))

            # ------------------------------------------------------------------
            # SCENE 3: Inventory, Offline Licensing, LAN Sync (15.4s - 26.6s)
            # ------------------------------------------------------------------
            elif 15.4 <= time_sec < 26.6:
                scene_time = time_sec - 15.4
                t_in = smoothstep(0, 1.2, scene_time)

                # Show Licensing Center & Catalog Screens
                pos_x = int(-200 + 280 * t_in)
                
                # License shot (top)
                if license_shot:
                    s1 = license_shot.resize((1040, 360), Image.Resampling.LANCZOS)
                    draw.rounded_rectangle([pos_x - 5, 145, pos_x + 1045, 510], radius=14, fill=(0, 0, 0, 160))
                    frame.alpha_composite(s1, (pos_x, 150))
                    draw.rounded_rectangle([pos_x, 150, pos_x + 1040, 510], radius=14, outline=(16, 185, 129, 180), width=2)

                # Catalog shot (bottom)
                if catalog_shot:
                    s2 = catalog_shot.resize((1040, 360), Image.Resampling.LANCZOS)
                    draw.rounded_rectangle([pos_x - 5, 535, pos_x + 1045, 900], radius=14, fill=(0, 0, 0, 160))
                    frame.alpha_composite(s2, (pos_x, 540))
                    draw.rounded_rectangle([pos_x, 540, pos_x + 1040, 900], radius=14, outline=(0, 229, 255, 180), width=2)

                # Right Feature Pillars
                card_x = int(width + 400 - 640 * t_in)
                
                # Pillar 1: Ed25519 Cryptographic Licensing
                p1_y = 150
                draw.rounded_rectangle([card_x, p1_y, card_x + 560, p1_y + 220], radius=16, fill=(11, 20, 38, 240), outline=(16, 185, 129, 200), width=2)
                draw.text((card_x + 30, p1_y + 20), render_arabic_text("🛡️ أمان مشفر وتراخيص عتادية"), font=font_card_title, fill=(52, 211, 153, 255))
                lines_p1 = [
                    "• تشفير رقمي Ed25519 ببصمة العتاد",
                    "• يعمل 100% دون الحاجة للإنترنت",
                    "• حماية كاملة ضد النسخ والقرصنة"
                ]
                for i, l in enumerate(lines_p1):
                    draw.text((card_x + 35, p1_y + 70 + i * 42), render_arabic_text(l), font=font_card_body, fill=(241, 245, 249, 255))

                # Pillar 2: Real LAN Sync & Offline Resilience
                p2_y = 395
                draw.rounded_rectangle([card_x, p2_y, card_x + 560, p2_y + 220], radius=16, fill=(11, 20, 38, 240), outline=(0, 229, 255, 200), width=2)
                draw.text((card_x + 30, p2_y + 20), render_arabic_text("🔄 مزامنة شبكية محلية (Real LAN)"), font=font_card_title, fill=(0, 229, 255, 255))
                lines_p2 = [
                    "• ربط أجهزة الكاشير مع السيرفر المحلي",
                    "• عمل مستمر حتى عند انقطاع الشبكة",
                    "• مزامنة عكسية فورية عند عودة الاتصال"
                ]
                for i, l in enumerate(lines_p2):
                    draw.text((card_x + 35, p2_y + 70 + i * 42), render_arabic_text(l), font=font_card_body, fill=(241, 245, 249, 255))

                # Pillar 3: Inventory & Warehouses
                p3_y = 640
                draw.rounded_rectangle([card_x, p3_y, card_x + 560, p3_y + 220], radius=16, fill=(11, 20, 38, 240), outline=(245, 158, 11, 200), width=2)
                draw.text((card_x + 30, p3_y + 20), render_arabic_text("📦 إدارة المخازن والمستودعات"), font=font_card_title, fill=(251, 191, 36, 255))
                lines_p3 = [
                    "• جرد لحظي وتقييم بضاعة دقيق",
                    "• تحويلات بين الفروع والمستودعات",
                    "• تنبيهات ذكية قبل نفاد الكميات"
                ]
                for i, l in enumerate(lines_p3):
                    draw.text((card_x + 35, p3_y + 70 + i * 42), render_arabic_text(l), font=font_card_body, fill=(241, 245, 249, 255))

            # ------------------------------------------------------------------
            # SCENE 4: Grand Finale & Call to Action (26.6s - 34.0s)
            # ------------------------------------------------------------------
            else:
                scene_time = time_sec - 26.6
                t_in = smoothstep(0, 1.0, scene_time)
                
                cx = width // 2
                # Big Central Logo
                icon_size = 240
                icon_resized = app_icon.resize((icon_size, icon_size), Image.Resampling.LANCZOS)
                
                cy = 280
                glow_r = 180 + int(20 * math.sin(scene_time * 3))
                draw.ellipse([cx - glow_r, cy - glow_r, cx + glow_r, cy + glow_r], fill=(0, 229, 255, 45))
                frame.alpha_composite(icon_resized, (cx - icon_size // 2, cy - icon_size // 2))

                # Main Hero Slogan
                hero_title = "ALFA SOFT ERP"
                draw.text((cx - 240, 430), hero_title, font=get_font(FONT_BOLD_PATH, 68), fill=(255, 255, 255, 255))
                
                slogan1 = render_arabic_text("سيطرة مطلقة على تجارتك... ارتقِ بأعمالك الآن")
                draw.text((cx - 380, 520), slogan1, font=font_title, fill=(0, 229, 255, 255))

                # 4 Core Value Propositions
                v_y = 620
                cards = [
                    ("⚡ سرعة وأداء مكتبي أصيل", cx - 640),
                    ("🔒 تشفير عالي وأمان دائم", cx - 310),
                    ("💰 دعم تعدد العملات والضريبة", cx + 20),
                    ("🔄 مزامنة شبكية دون إنترنت", cx + 350)
                ]
                for text_val, vx in cards:
                    draw.rounded_rectangle([vx, v_y, vx + 310, v_y + 60], radius=30, fill=(15, 23, 42, 230), outline=(0, 229, 255, 140), width=2)
                    draw.text((vx + 25, v_y + 14), render_arabic_text(text_val), font=get_font(FONT_ARABIC_BOLD, 20), fill=(241, 245, 249, 255))

                # Grand CTA Banner
                cta_y = 730
                cta_w = 880
                cta_x = cx - cta_w // 2
                draw.rounded_rectangle([cta_x, cta_y, cta_x + cta_w, cta_y + 90], radius=45, fill=(16, 185, 129, 240), outline=(255, 255, 255, 220), width=3)
                cta_text = render_arabic_text("★ اطلب نسختك المرخصة الآن — ALFA SOFT Enterprise ★")
                draw.text((cta_x + 90, cta_y + 24), cta_text, font=get_font(FONT_ARABIC_BOLD, 30), fill=(255, 255, 255, 255))

            # ------------------------------------------------------------------
            # LOWER SUBTITLES & TICKER BAR (Synced with Voiceover)
            # ------------------------------------------------------------------
            sub_y = height - 100
            draw.rectangle([0, sub_y, width, height], fill=(8, 14, 28, 245))
            draw.line([(0, sub_y), (width, sub_y)], fill=(0, 229, 255, 160), width=2)

            # Find active subtitle
            active_sub = ""
            for s_start, s_end, text in subtitles:
                if s_start <= time_sec <= s_end:
                    active_sub = text
                    break

            if active_sub:
                reshaped_sub = render_arabic_text(active_sub)
                # Center text horizontally
                bbox = draw.textbbox((0, 0), reshaped_sub, font=font_ticker)
                text_w = bbox[2] - bbox[0]
                text_x = (width - text_w) // 2
                # Subtitle text with subtle glow
                draw.text((text_x, sub_y + 30), reshaped_sub, font=font_ticker, fill=(255, 255, 255, 255))

            # Write RGB24 frame to FFmpeg stdin pipe
            frame_rgb = frame.convert("RGB")
            proc.stdin.write(frame_rgb.tobytes())

            if f % 150 == 0:
                print(f"Rendered {f}/{total_frames} frames ({f/total_frames*100:.1f}%)...")

    finally:
        proc.stdin.close()
        stdout_data, stderr_data = proc.communicate()
        proc.wait()

    if proc.returncode == 0:
        print(f"\n★ Commercial Video Rendered Successfully at: {output_video_path} ★")
    else:
        print(f"FFmpeg error:\n{stderr_data.decode('utf-8', errors='ignore')}")

if __name__ == "__main__":
    render_promo_video()
