Class ZPM.Tests.DiskStreams Extends %UnitTest.TestCase
{

Parameter NAME = "unittest-disk-streams";

Parameter CHANNEL = "unittest";

Parameter VERSION = "0.0.1";

Method OnBeforeAllTests() As %Status
{
    Do ..Cleanup()
    Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
    Do ..Cleanup()
    Quit $$$OK
}

ClassMethod Cleanup()
{
    Set tPkg = ##class(ZPM.Package).NameChannelVersionOpen(..#NAME, ..#CHANNEL, ..#VERSION, , .tSC)
    If $IsObject(tPkg) {
        Do ##class(ZPM.Package).%DeleteId(tPkg.%Id())
    }
    Do ##class(ZPM.PackageStorage).DeleteVersionDirectory(..#NAME, ..#CHANNEL, ..#VERSION)
}

Method TestBytesLiveOnDisk()
{
    Do ..Cleanup()

    Set tPkg = ##class(ZPM.Package).%New()
    Set tPkg.name = ..#NAME
    Set tPkg.channel = ..#CHANNEL
    Set tPkg.version = ..#VERSION
    Set tPkg.description = "disk stream unit test"

    Set tBin = ##class(%Stream.FileBinary).%New()
    Set tBin.Filename = ##class(%File).TempFilename("tgz")
    Do tBin.Write("payload-bytes")
    Set tPkg.package = tBin

    Set tMan = ##class(%Stream.FileCharacter).%New()
    Set tMan.Filename = ##class(%File).TempFilename("xml")
    Do tMan.Write("<Module><Name>" _ ..#NAME _ "</Name><Version>" _ ..#VERSION _ "</Version></Module>")
    Set tPkg.manifest = tMan

    Set tSC = tPkg.%Save()
    Do $$$AssertStatusOK(tSC)
    Set tId = tPkg.%Id()

    Set tArchive = ##class(ZPM.PackageStorage).ArchivePath(..#NAME, ..#CHANNEL, ..#VERSION)
    Set tManifest = ##class(ZPM.PackageStorage).ManifestPath(..#NAME, ..#CHANNEL, ..#VERSION)
    Do $$$AssertTrue(##class(%File).Exists(tArchive), "archive exists on disk")
    Do $$$AssertTrue(##class(%File).Exists(tManifest), "manifest exists on disk")

    Do $$$AssertTrue(tPkg.package.%IsA("%Stream.FileBinary"), "package property is a file stream")
    Do $$$AssertEquals(##class(%File).NormalizeFilename(tPkg.package.Filename), tArchive, "package property points at the archive")

    Do $$$AssertEquals($Data(^ZPM.PackageS), 0, "no legacy stream global chunks")

    Set tStream = tPkg.GetPackageStream()
    Do $$$AssertTrue($IsObject(tStream), "GetPackageStream returns a stream")
    Do $$$AssertEquals(tStream.Read(1000), "payload-bytes", "package bytes served from disk")
    Do tStream.%Close()

    Set tReloaded = ##class(ZPM.Package).%OpenId(tId)
    Do $$$AssertTrue($IsObject(tReloaded), "package reloads")
    Set tDisk = tReloaded.GetPackageStream()
    Do $$$AssertTrue($IsObject(tDisk), "reloaded package serves a stream")
    Do $$$AssertEquals(tDisk.Read(1000), "payload-bytes", "reloaded bytes served from disk")
    Do tDisk.%Close()

    Set tManifestStream = tReloaded.GetManifestStream()
    Do $$$AssertTrue($IsObject(tManifestStream), "manifest stream available")
    Set tManifestText = tManifestStream.Read(1000)
    Do $$$AssertTrue(tManifestText [ "<Name>" _ ..#NAME _ "</Name>", "manifest served from disk")
    Do tManifestStream.%Close()

    Do ..Cleanup()
    Do $$$AssertTrue('##class(%File).Exists(tArchive), "cleanup removed the archive")
}

}
