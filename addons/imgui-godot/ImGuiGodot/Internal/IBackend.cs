#if GODOT_PC
#nullable enable
using Godot;

namespace ImGuiGodot.Internal;

internal interface IBackend
{
    public bool Visible { get; set; }
    public float JoyAxisDeadZone { get; set; }
    public float Scale { get; set; }
    public void ResetFonts();
    public void AddFont(FontFile fontData, int fontSize, bool merge, ushort[]? glyphRanges);
    public void AddFontDefault();
    public void RebuildFontAtlas();
    public void Connect(Callable callable);
    public void SetMainViewport(Viewport vp);
    public bool SubViewportWidget(SubViewport svp);
    public void SetIniFilename(string filename);
}
#endif
