// Native.cs — вызовы Win32, нужные трею и значку у клиента.
using System;
using System.Runtime.InteropServices;
using System.Text;

static class Native {
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    public delegate void WinEventProc(IntPtr hook, uint ev, IntPtr hwnd, int idObject, int idChild, uint thread, uint time);

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }

    public const int GWL_EXSTYLE = -20, GWL_HWNDPARENT = -8;
    public const int WS_EX_TOOLWINDOW = 0x80, WS_EX_NOACTIVATE = 0x08000000;
    public const uint SWP_NOSIZE = 1, SWP_NOZORDER = 4, SWP_NOACTIVATE = 0x10;
    public const uint EVENT_SYSTEM_MINIMIZESTART = 0x16, EVENT_SYSTEM_MINIMIZEEND = 0x17;
    public const uint EVENT_OBJECT_DESTROY = 0x8001, EVENT_OBJECT_SHOW = 0x8002, EVENT_OBJECT_HIDE = 0x8003, EVENT_OBJECT_LOCATIONCHANGE = 0x800B;

    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder sb, int max);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll", EntryPoint = "GetWindowLongW")] public static extern int GetWindowLong(IntPtr h, int idx);
    [DllImport("user32.dll", EntryPoint = "SetWindowLongW")] static extern int SetWindowLong32(IntPtr h, int idx, int v);
    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW")] static extern IntPtr SetWindowLongPtr64(IntPtr h, int idx, IntPtr v);
    [DllImport("user32.dll")] public static extern IntPtr SetWinEventHook(uint min, uint max, IntPtr mod, WinEventProc proc, uint pid, uint thread, uint flags);
    [DllImport("user32.dll")] public static extern bool UnhookWinEvent(IntPtr hook);
    [DllImport("user32.dll")] public static extern bool DestroyIcon(IntPtr h);
    [DllImport("psapi.dll")] public static extern bool EmptyWorkingSet(IntPtr h);

    // Владелец окна (GWL_HWNDPARENT): значок всегда над окном клиента, но не над остальными.
    public static void SetOwner(IntPtr h, IntPtr owner) {
        if (IntPtr.Size == 8) SetWindowLongPtr64(h, GWL_HWNDPARENT, owner);
        else SetWindowLong32(h, GWL_HWNDPARENT, owner.ToInt32());
    }

    public static void AddExStyle(IntPtr h, int bits) {
        SetWindowLong32(h, GWL_EXSTYLE, GetWindowLong(h, GWL_EXSTYLE) | bits);
    }
}
