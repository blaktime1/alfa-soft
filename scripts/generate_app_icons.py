import os
from PIL import Image

def generate_icons():
    source_image_path = r"C:\Users\MAX\.gemini\antigravity-ide\brain\093d92de-e6a7-4a6a-8fcf-2ebca7ab7af1\.user_uploaded\media_1794054438604.jpg"
    base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    
    images_dir = os.path.join(base_dir, "assets", "images")
    icons_dir = os.path.join(base_dir, "assets", "icons")
    windows_res_dir = os.path.join(base_dir, "windows", "runner", "resources")
    installer_dir = os.path.join(base_dir, "installer")
    
    os.makedirs(images_dir, exist_ok=True)
    os.makedirs(icons_dir, exist_ok=True)
    os.makedirs(windows_res_dir, exist_ok=True)
    os.makedirs(installer_dir, exist_ok=True)
    
    print(f"Loading source image from: {source_image_path}")
    img = Image.open(source_image_path).convert("RGBA")
    
    # 1. Save master app logo
    master_png = os.path.join(images_dir, "app_logo.png")
    img.save(master_png, "PNG")
    print(f"Saved master logo: {master_png} ({img.size})")
    
    # 2. Save individual PNG sizes
    sizes = [16, 24, 32, 48, 64, 128, 256, 512, 1024]
    for s in sizes:
        resized = img.resize((s, s), Image.Resampling.LANCZOS)
        out_path = os.path.join(icons_dir, f"app_icon_{s}.png")
        resized.save(out_path, "PNG")
        print(f"Saved PNG icon: {out_path}")
        
    # 3. Generate multi-resolution Windows ICO
    ico_sizes = [(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]
    windows_ico_path = os.path.join(windows_res_dir, "app_icon.ico")
    img.save(windows_ico_path, format="ICO", sizes=ico_sizes)
    print(f"Generated Windows App Icon: {windows_ico_path}")
    
    # 4. Copy to Inno Setup installer
    installer_ico_path = os.path.join(installer_dir, "app_icon.ico")
    img.save(installer_ico_path, format="ICO", sizes=ico_sizes)
    print(f"Generated Installer Icon: {installer_ico_path}")
    
    print("All icons successfully generated!")

if __name__ == "__main__":
    generate_icons()
