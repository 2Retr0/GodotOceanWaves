#if GODOT_PC
#nullable enable
using Godot;
using ImGuiNET;
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

using SharedList = ImGuiGodot.Internal.DisposableList<Godot.Rid,
    ImGuiGodot.Internal.ClonedDrawData>;

namespace ImGuiGodot.Internal;

internal sealed class ClonedDrawData : IDisposable
{
    public ImDrawDataPtr Data { get; private set; }

    public unsafe ClonedDrawData(ImDrawDataPtr inp)
    {
        // deep swap is difficult because ImGui still owns the draw lists
        // TODO: revisit when Godot's threaded renderer is stable

        long ddsize = Marshal.SizeOf<ImDrawData>();

        // start with a shallow copy
        Data = new(ImGui.MemAlloc((uint)ddsize));
        Buffer.MemoryCopy(inp.NativePtr, Data.NativePtr, ddsize, ddsize);

        // clone the draw data
        int numLists = inp.CmdLists.Size;
        IntPtr cmdListPtrs = ImGui.MemAlloc((uint)(Marshal.SizeOf<IntPtr>() * numLists));
        Data.NativePtr->CmdLists = new ImVector(numLists, numLists, cmdListPtrs);
        for (int i = 0; i < inp.CmdLists.Size; ++i)
        {
            Data.CmdLists[i] = (IntPtr)inp.CmdLists[i].CloneOutput().NativePtr;
        }
    }

    public unsafe void Dispose()
    {
        if (Data.NativePtr == null)
            return;

        for (int i = 0; i < Data.CmdListsCount; ++i)
        {
            Data.CmdLists[i].Destroy();
        }
        Data.Destroy();
        Data = new(null);
    }
}

internal sealed class DisposableList<T, U> : List<Tuple<T, U>>, IDisposable where U : IDisposable
{
    public DisposableList() { }
    public DisposableList(int capacity) : base(capacity) { }

    public void Dispose()
    {
        foreach (var tuple in this)
        {
            tuple.Item2.Dispose();
        }
        Clear();
    }
}

internal sealed class RdRendererThreadSafe : RdRenderer, IRenderer
{
    public new string Name => "godot4_net_rd_mt";

    private readonly object _sharedDataLock = new();
    private SharedList? _dataToDraw;

    public RdRendererThreadSafe()
    {
        // draw on the renderer thread to avoid conflicts
        RenderingServer.FramePreDraw += OnFramePreDraw;
    }

    ~RdRendererThreadSafe()
    {
        RenderingServer.FramePreDraw -= OnFramePreDraw;
    }

    public new void Render()
    {
        var pio = ImGui.GetPlatformIO();
        var newData = new SharedList(pio.Viewports.Size);

        for (int i = 0; i < pio.Viewports.Size; ++i)
        {
            var vp = pio.Viewports[i];
            if (vp.Flags.HasFlag(ImGuiViewportFlags.IsMinimized))
                continue;

            ReplaceTextureRids(vp.DrawData);
            Rid vprid = Util.ConstructRid((ulong)vp.RendererUserData);
            newData.Add(new(GetFramebuffer(vprid), new(vp.DrawData)));
        }

        lock (_sharedDataLock)
        {
            // if a frame was skipped, free old data
            _dataToDraw?.Dispose();
            _dataToDraw = newData;
        }
    }

    private SharedList TakeSharedData()
    {
        lock (_sharedDataLock)
        {
            var rv = _dataToDraw;
            _dataToDraw = null;
            return rv ?? [];
        }
    }

    private void OnFramePreDraw()
    {
        // take ownership of shared data
        using SharedList dataArray = TakeSharedData();

        foreach (var kv in dataArray)
        {
            if (RD.FramebufferIsValid(kv.Item1))
                RenderOne(kv.Item1, kv.Item2.Data);
        }

        FreeUnusedTextures();
    }
}
#endif
