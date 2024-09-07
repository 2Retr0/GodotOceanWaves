#if GODOT_PC
using Godot;
using System;

namespace ImGuiGodot.Internal;

internal interface IRenderer : IDisposable
{
    public string Name { get; }
    public void InitViewport(Rid vprid);
    public void CloseViewport(Rid vprid);
    public void Render();
    public void OnHide();
}
#endif
