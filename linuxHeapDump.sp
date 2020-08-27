#include <MemoryEx/Stocks>

static const char g_sSMXMagic[] = "FFPS";
static const char outPutDir[] = "/memoryDump";

enum struct HeapInfo // very bad.  same as in DynamicLibrary.
{
    Address base;
    Address end;

    int GetSize()
    {
        return view_as<int>(this.end - this.base);
    }
    void FillFromBuffer(const char[] sBuffer)
    {
        char sBaseAddress[16];
        char sEndAddress[16];

        FormatEx(sBaseAddress, 9, "%s", sBuffer);
        FormatEx(sEndAddress, 9, "%s", sBuffer[9]);

        this.base = view_as<Address>(HexToDec(sBaseAddress));
        this.end = view_as<Address>(HexToDec(sEndAddress));
    }
}
//https://github.com/alliedmodders/sourcepawn/blob/c44a169030f09df9a72506242d09d5eb76c13534/include/smx/smx-headers.h
enum struct VM_SMXHeader
{
    Address addr;
    int size;
/*
    int section;
    int stringTab;
    int dataoffs;*/

    bool IsValid(Address pBase)
    {
        int version = LoadFromAddress(pBase + view_as<Address>(0x04), NumberType_Int16);

        if(version != 0x0102) // 0x0200 - Used by spcomp2 - not supported
        {
            return false;
        }

        int compress = LoadFromAddress(pBase + view_as<Address>(0x06), NumberType_Int8);

        if(compress != 0 && compress != 1)
        {
            return false;
        }

        return true;
    }
    void FillInfo(Address pBase)
    {
        this.addr = pBase;

        this.size       = LoadFromAddress(pBase + view_as<Address>(0x0B), NumberType_Int32);
        /*
        this.section    = LoadFromAddress(pBase + view_as<Address>(0x0F), NumberType_Int8);
        this.stringTab  = LoadFromAddress(pBase + view_as<Address>(0x10), NumberType_Int32);
        this.dataoffs   = LoadFromAddress(pBase + view_as<Address>(0x14), NumberType_Int32);*/
    }
}
public void OnPluginStart()
{
    RegServerCmd("sm_dump_smx", Cmd_Dump_Smx);
    RegServerCmd("sm_dump_heaps", Cmd_Dump_Heaps);
}
public Action Cmd_Dump_Smx(int iArgs)
{
    PrintToServer("----------Start Dump SMX from Memory----------");
    DumpPlugins();
    PrintToServer("----------End Dump SMX from Memory----------");
}
public Action Cmd_Dump_Heaps(int iArgs)
{
    PrintToServer("----------Start Dump Heaps from Memory----------");
    
    ArrayList heaps = DumpHeaps(true);
    HeapInfo memInfo;

    Address offsetSize;
    int iSize;
    int iCurrentSize;

    static const int iMaxHeapSize = 0x1C9C380;

    PrintToServer("Heaps count: %d", heaps.Length);

    ArrayList heapsRegion = new ArrayList(sizeof(HeapInfo));
    HeapInfo memTemp;

    for(int x = 0; x < heaps.Length; x++)
    {
        heaps.GetArray(x, memInfo, sizeof(HeapInfo));
        iSize = memInfo.GetSize();

        PrintToServer("Dump Heaps: Start: 0x%X | End: 0x%X | Size: 0x%X", memInfo.base, memInfo.end, memInfo.GetSize());

        if(iSize >= iMaxHeapSize) // 30 MB
        {
            offsetSize = Address_Null;

            while(iSize > 0)
            {
                iCurrentSize = iSize >= iMaxHeapSize ? iMaxHeapSize : iSize;
                PrintToServer("\tDump Part heap[0x%X-0x%X] Start: 0x%X | End: 0x%X | Size: 0x%X|0x%X [> 0x%X[%d]]", 
				memInfo.base, memInfo.end, memInfo.base + offsetSize, memInfo.base + offsetSize + view_as<Address>(iCurrentSize), iCurrentSize, iSize, iMaxHeapSize, iSize >= iMaxHeapSize);

                memTemp.base = memInfo.base + offsetSize;
                memTemp.end = memInfo.base + offsetSize + view_as<Address>(iCurrentSize);

                heapsRegion.PushArray(memTemp, sizeof(HeapInfo));

                offsetSize += view_as<Address>(iCurrentSize);
                iSize -= iCurrentSize;
            }
        }
        else
        {
            CreateHeapMemoryDump(heapsRegion, memInfo.base, iSize);
        }
    }

    HeapDumpFrame_(null, heapsRegion);
}
public Action HeapDumpFrame_(Handle hTimer, ArrayList heaps)
{

    HeapInfo heap;

    if(heaps.Length)
    {
        heaps.GetArray(0, heap, sizeof(HeapInfo));
        heaps.Erase(0);

        CreateHeapMemoryDump(heaps, heap.base, heap.GetSize());
    }
    else
    {
        PrintToServer("----------End Dump Heaps from Memory----------");
        delete heaps
    }
}
void DumpPlugins()
{
    ArrayList plugins = VM_GetValidPlugins();

    VM_SMXHeader smx;

    char sName[8];

    for(int x = 0; x < plugins.Length; x++)
    {
        plugins.GetArray(x, smx, sizeof(VM_SMXHeader));

        FormatEx(sName, sizeof sName, "%d.smx", x);
        CreateMemoryDump(sName, smx.addr, smx.size);
    }
}
void CreateHeapMemoryDump(ArrayList heaps, Address pBase, any iSize)
{
    char sNewPath[PLATFORM_MAX_PATH];

    if(!DirExists(outPutDir))
    {
        CreateDirectory(outPutDir, 511);
    }

    FormatEx(sNewPath, sizeof sNewPath, "%s/%X-%X.txt", outPutDir, pBase, pBase + view_as<Address>(iSize));

    if(FileExists(sNewPath))
    {
        if(!DeleteFile(sNewPath))
        {
            SetFailState("CreateMemoryDump couldn't delete file %s", sNewPath);
        }
    }

    File outPut = OpenFile(sNewPath, "ab");

    if(outPut == null)
    {
        SetFailState("file == null");
    }

    static const int iMaxColum = 0x10;


    char sLine[512];
    int offset;
    int[] bytes = new int[iMaxColum];

    Address end = pBase + view_as<Address>(iSize);

    while(pBase < end) 
    {
        int iByte = LoadFromAddress(pBase, NumberType_Int8);

        if(offset >= iMaxColum)
        {
            offset = 0x00;

            outPut.WriteLine("%s    %c%c%c%c%c%c%c%c%c%c%c%c%c%c%c%c", sLine,  bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8],
            bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]);
            //LogError("%s", sLine);
        }

        if(iByte <= 0x20)
        {
            bytes[offset] = 0x2E;
        }
        else
        {
            bytes[offset] = iByte;
        }

        if(!offset)
        {
            FormatEx(sLine, sizeof sLine, "[0x%08X]", pBase);
        }

        Format(sLine, sizeof sLine, "%s [0x%02X]", sLine, iByte);

        offset++;
        pBase++;
    }

    delete outPut;

    PrintToServer("CreateHeapMemoryDump: %X-%X - complete %d...", pBase - view_as<Address>(iSize), end, heaps.Length);
    CreateTimer(1.0, HeapDumpFrame_, heaps, TIMER_FLAG_NO_MAPCHANGE)
}
void CreateMemoryDump(const char[] sFileName, Address pBase, any iSize)
{
    char sNewPath[PLATFORM_MAX_PATH];

    if(!DirExists(outPutDir))
    {
        CreateDirectory(outPutDir, 511);
    }

    FormatEx(sNewPath, sizeof sNewPath, "%s/%s", outPutDir, sFileName);

    if(FileExists(sNewPath))
    {
        if(!DeleteFile(sNewPath))
        {
            SetFailState("CreateMemoryDump couldn't delete file %s", sNewPath);
        }
    }

    File outPut = OpenFile(sNewPath, "ab");

    if(outPut == null)
    {
        SetFailState("file == null");
    }

    // Исправление smx header
    outPut.WriteString(g_sSMXMagic, false);
    outPut.WriteInt16(LoadFromAddress(pBase + view_as<Address>(0x04), NumberType_Int16));
    outPut.WriteInt8(0x00);
    outPut.WriteInt32(iSize);

    pBase += view_as<Address>(0x0B);

    Address end = pBase + view_as<Address>(iSize);

    while(pBase < end) // Очень плохая реализация
    {
        outPut.WriteInt8(LoadFromAddress(pBase, NumberType_Int8));
        pBase++;
    }
    
    delete outPut;
}
ArrayList VM_GetValidPlugins()
{
    ArrayList plugins = VM_GetPluginsBase();
    ArrayList res = new ArrayList(sizeof(VM_SMXHeader));

    VM_SMXHeader smx;
    Address pBase;

    for(int x = 0; x < plugins.Length; x++)
    {
        pBase = view_as<Address>(plugins.Get(x));

        if(!smx.IsValid(pBase))
        {
            continue;
        }

        smx.FillInfo(pBase);
        res.PushArray(smx, sizeof(VM_SMXHeader));
    }

    delete plugins;
    return res;
}
ArrayList VM_GetPluginsBase()
{
    ArrayList heaps = DumpHeaps(true);

    HeapInfo memInfo;

    ArrayList hPlugins = new ArrayList();

    PrintToServer("Heaps: %d", heaps.Length);

    for(int x = 0; x < heaps.Length; x++)
    {
        heaps.GetArray(x, memInfo, sizeof(HeapInfo));
        PrintToServer("VM_GetPluginsBase: region %X-%X | %X", memInfo.base, memInfo.end, memInfo.GetSize());

        ArrayList res = FindAllStrings(memInfo.base, memInfo.GetSize(), g_sSMXMagic);

        for(int y = 0; y < res.Length; y++)
        {
            hPlugins.Push(res.Get(y));
        }

        delete res;
    }

	return hPlugins;
}
ArrayList DumpHeaps(bool bRefresh = false)
{
    static ArrayList list;

    if(list == null)
    {
        list = new ArrayList(sizeof(HeapInfo));
    }
    else if(bRefresh)
    {
        list.Clear();
    }
    else if(list.Length != 0)
    {
        return list;
    }

    char sName[64];
    char sBuffer[1024];

    int iLength;
    int iOffset;
    File file = OpenFile("file:///proc/self/maps", "rt");

    HeapInfo info;

    while(file.ReadLine(sBuffer, sizeof sBuffer))
    {
        TrimString(sBuffer);
        iLength = strlen(sBuffer);

        LogError(sBuffer);

        if(sBuffer[iLength - 1] == '0' && sBuffer[iLength - 2] == ' ')
        {
            if(sBuffer[18] == 'r') // read
            {
                info.FillFromBuffer(sBuffer);
                list.PushArray(info, sizeof(HeapInfo));
            }
        }
        else if(sBuffer[iLength - 1] == ']')
        {
            iOffset = 0;
            strcopy(sName, sizeof sName, "");

            //LogError(sBuffer);

            for(int x = iLength - 2; x >= 0; x--, iOffset++)
            {
                if(sBuffer[x] == '[')
                {
                    strcopy(sName, iOffset + 1, sBuffer[x + 1]);
                    PrintToServer(sName);
                    if(!strcmp(sName, "heap"))
                    {

                        info.FillFromBuffer(sBuffer);
                        list.PushArray(info, sizeof(HeapInfo));
                    }
                    break;
                }
            }
        }
    }
//LogError("name %s base %s|0x%X end %s|0x%X size 0x%X", sName, sBaseAddress, info.base, sEndAddress, info.end, info.GetSize());
    delete file;
    return list;
}