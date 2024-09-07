#if GODOT_PC
using Godot;
using System;
using System.Reflection;
using System.Reflection.Emit;

namespace ImGuiGodot.Internal;

internal static class Util
{
    public static readonly Func<ulong, Rid> ConstructRid;

    static Util()
    {
        ConstructorInfo cinfo = typeof(Rid).GetConstructor(
            BindingFlags.NonPublic | BindingFlags.Instance,
            [typeof(ulong)]) ??
            throw new PlatformNotSupportedException("failed to get Rid constructor");
        DynamicMethod dm = new("ConstructRid", typeof(Rid), [typeof(ulong)]);
        ILGenerator il = dm.GetILGenerator();
        il.Emit(OpCodes.Ldarg_0);
        il.Emit(OpCodes.Newobj, cinfo);
        il.Emit(OpCodes.Ret);
        ConstructRid = dm.CreateDelegate<Func<ulong, Rid>>();
    }
}
#endif
