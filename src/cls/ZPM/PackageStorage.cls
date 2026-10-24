Include %occStatus

/// On-disk layout for package archives and sidecar streams under Settings.GetPackageFilesRoot().
Class ZPM.PackageStorage Extends %RegisteredObject
{

Parameter ARCHIVENAME = "package.tgz";

Parameter MANIFESTNAME = "module.xml";

Parameter INSTALLERNAME = "installer.xml";

ClassMethod NormalizeDir(path As %String) As %String
{
    Set p = ##class(%File).NormalizeDirectory($Get(path))
    Return p
}

/// Sanitize a path segment (package name, channel, version) for the host filesystem.
ClassMethod SafeSegment(value As %String) As %String
{
    Set value = $ZStrip($Get(value), "<>W")
    If value = "" Return "_"
    Set out = ""
    For i = 1:1:$Length(value) {
        Set ch = $Extract(value, i)
        If ch?1AN Set out = out _ ch
        ElseIf (ch = "-") || (ch = "_") || (ch = ".") Set out = out _ ch
        Else Set out = out _ "_"
    }
    Return out
}

ClassMethod PackagesRoot() As %String
{
    Return ..NormalizeDir(##class(%File).SubDirectoryName(##class(ZPM.Settings).GetPackageFilesRoot(), "packages"))
}

ClassMethod VersionDirectory(name As %String, channel As %String, version As %String) As %String
{
    Set name = ..SafeSegment($$$lcase(name))
    Set channel = ..SafeSegment(channel)
    Set version = ..SafeSegment(version)
    Set dir = ##class(%File).SubDirectoryName(..PackagesRoot(), name)
    Set dir = ##class(%File).SubDirectoryName(dir, channel)
    Set dir = ##class(%File).SubDirectoryName(dir, version)
    Return ..NormalizeDir(dir)
}

ClassMethod ArchivePath(name As %String, channel As %String, version As %String) As %String
{
    Return ##class(%File).NormalizeFilename(..#ARCHIVENAME, ..VersionDirectory(name, channel, version))
}

ClassMethod ManifestPath(name As %String, channel As %String, version As %String) As %String
{
    Return ##class(%File).NormalizeFilename(..#MANIFESTNAME, ..VersionDirectory(name, channel, version))
}

ClassMethod InstallerPath(name As %String, channel As %String, version As %String) As %String
{
    Return ##class(%File).NormalizeFilename(..#INSTALLERNAME, ..VersionDirectory(name, channel, version))
}

ClassMethod PathUnderRoot(fullPath As %String, root As %String) As %Boolean
{
    Set fullPath = ..NormalizeDir(fullPath)
    Set root = ..NormalizeDir(root)
    If root = "" Return 0
    If $Length(fullPath) < $Length(root) Return 0
    If $Extract(fullPath, 1, $Length(root)) '= root Return 0
    If $Length(fullPath) = $Length(root) Return 1
    Set sep = $Extract(fullPath, $Length(root) + 1, $Length(root) + 1)
    Return (sep = "/") || (sep = "\")
}

ClassMethod EnsureVersionDirectory(name As %String, channel As %String, version As %String, Output errMsg As %String) As %Boolean
{
    Set errMsg = ""
    Set dir = ..VersionDirectory(name, channel, version)
    If '##class(%File).CreateDirectoryChain(dir) {
        Set errMsg = "unable to create package directory"
        Return 0
    }
    Return 1
}

ClassMethod DeleteVersionDirectory(name As %String, channel As %String, version As %String) As %Status
{
    Set dir = ..VersionDirectory(name, channel, version)
    If '##class(%File).DirectoryExists(dir) {
        Return $$$OK
    }
    If '..PathUnderRoot(dir, ..PackagesRoot()) {
        Return $$$ERROR($$$GeneralError, "refusing to delete path outside package root")
    }
    If '##class(%File).RemoveDirectoryTree(dir) {
        Return $$$ERROR($$$GeneralError, "unable to remove package directory")
    }
    Return $$$OK
}

ClassMethod DiskArchiveSize(name As %String, channel As %String, version As %String) As %Integer
{
    Set path = ..ArchivePath(name, channel, version)
    If '##class(%File).Exists(path) Return 0
    Return +##class(%File).GetSize(path)
}

ClassMethod DiskArchiveExists(name As %String, channel As %String, version As %String) As %Boolean
{
    Set path = ..ArchivePath(name, channel, version)
    Return ##class(%File).Exists(path) && (##class(%File).GetSize(path) > 0)
}

ClassMethod OpenDiskArchive(name As %String, channel As %String, version As %String) As %Stream.FileBinary
{
    Set path = ..ArchivePath(name, channel, version)
    If '##class(%File).Exists(path) Return ""
    Set stream = ##class(%Stream.FileBinary).%New()
    If $$$ISERR(stream.LinkToFile(path)) Return ""
    Return stream
}

/// Host-level copy (or rename when <var>sourcePath</var> already equals <var>destPath</var>). Preserves exact file bytes.
ClassMethod InstallFileFromPath(sourcePath As %String, destPath As %String, Output errMsg As %String) As %Status
{
    Set errMsg = ""
    Set sourcePath = ##class(%File).NormalizeFilename(sourcePath)
    Set destPath = ##class(%File).NormalizeFilename(destPath)
    If sourcePath = destPath Return $$$OK
    If '##class(%File).Exists(sourcePath) {
        Set errMsg = "source file missing"
        Return $$$ERROR($$$GeneralError, errMsg)
    }
    Set tmpPath = destPath _ ".writing"
    If ##class(%File).Exists(tmpPath) {
        Do ##class(%File).Delete(tmpPath)
    }
    Set in = ##class(%Stream.FileBinary).%New()
    Set sc = in.LinkToFile(sourcePath)
    If $$$ISERR(sc) {
        Set errMsg = $System.Status.GetErrorText(sc)
        Return sc
    }
    Set bytes = 0
    Set sc = ..CopyStreamToFile(in, tmpPath, .bytes, .errMsg)
    If $$$ISERR(sc) Return sc
    If ##class(%File).Exists(destPath) {
        Do ##class(%File).Delete(destPath)
    }
    If '##class(%File).Rename(tmpPath, destPath) {
        Do ##class(%File).Delete(tmpPath)
        Set errMsg = "unable to install file"
        Return $$$ERROR($$$GeneralError, errMsg)
    }
    Return $$$OK
}

ClassMethod CopyStreamToFile(source As %Stream.Object, destPath As %String, Output bytesWritten As %Integer, Output errMsg As %String) As %Status
{
    Set bytesWritten = 0
    Set errMsg = ""
    If '$IsObject(source) {
        Set errMsg = "missing source stream"
        Return $$$ERROR($$$GeneralError, errMsg)
    }
    Do source.Rewind()
    Set tmpPath = destPath _ ".writing"
    If ##class(%File).Exists(tmpPath) {
        Do ##class(%File).Delete(tmpPath)
    }
    Set fileStream = ##class(%Stream.FileBinary).%New()
    Set sc = fileStream.LinkToFile(tmpPath)
    If $$$ISERR(sc) {
        Set errMsg = $System.Status.GetErrorText(sc)
        Return sc
    }
    Set sc = fileStream.CopyFrom(source)
    If $$$ISERR(sc) {
        Do ##class(%File).Delete(tmpPath)
        Set errMsg = $System.Status.GetErrorText(sc)
        Return sc
    }
    Set sc = fileStream.%Save()
    If $$$ISERR(sc) {
        Do ##class(%File).Delete(tmpPath)
        Set errMsg = $System.Status.GetErrorText(sc)
        Return sc
    }
    Set bytesWritten = +fileStream.Size
    // Close the handle first: Windows refuses to rename an open file.
    Kill fileStream
    If ##class(%File).Exists(destPath) {
        Do ##class(%File).Delete(destPath)
    }
    If '##class(%File).Rename(tmpPath, destPath) {
        Do ##class(%File).Delete(tmpPath)
        Set errMsg = "unable to finalize package file"
        Return $$$ERROR($$$GeneralError, errMsg)
    }
    Return $$$OK
}

ClassMethod CopyStreamToCharacterFile(source As %Stream.Object, destPath As %String, translateTable As %String = "UTF8", Output errMsg As %String) As %Status
{
    Set errMsg = ""
    If '$IsObject(source) Return $$$OK
    Do source.Rewind()
    If 'source.Size Return $$$OK
    Set tmpPath = destPath _ ".writing"
    If ##class(%File).Exists(tmpPath) Do ##class(%File).Delete(tmpPath)
    Set fileStream = ##class(%Stream.FileCharacter).%New()
    Set fileStream.TranslateTable = translateTable
    Set sc = fileStream.LinkToFile(tmpPath)
    If $$$ISERR(sc) {
        Set errMsg = $System.Status.GetErrorText(sc)
        Return sc
    }
    Set sc = fileStream.CopyFrom(source)
    If $$$ISERR(sc) {
        Do ##class(%File).Delete(tmpPath)
        Set errMsg = $System.Status.GetErrorText(sc)
        Return sc
    }
    Set sc = fileStream.%Save()
    If $$$ISERR(sc) {
        Do ##class(%File).Delete(tmpPath)
        Set errMsg = $System.Status.GetErrorText(sc)
        Return sc
    }
    // Close the handle first: Windows refuses to rename an open file.
    Kill fileStream
    If ##class(%File).Exists(destPath) Do ##class(%File).Delete(destPath)
    If '##class(%File).Rename(tmpPath, destPath) {
        Do ##class(%File).Delete(tmpPath)
        Set errMsg = "unable to finalize text file"
        Return $$$ERROR($$$GeneralError, errMsg)
    }
    Return $$$OK
}

ClassMethod OpenDiskCharacter(path As %String, translateTable As %String = "UTF8") As %Stream.FileCharacter
{
    If '##class(%File).Exists(path) Return ""
    Set stream = ##class(%Stream.FileCharacter).%New()
    Set stream.TranslateTable = translateTable
    If $$$ISERR(stream.LinkToFile(path)) Return ""
    Return stream
}

}
