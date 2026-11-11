Class ZPM.Tests.AdminRemoveVersion Extends %UnitTest.TestCase
{

Parameter NAME = "unittest-admin-remove";

Parameter CHANNEL = "unittest";

Parameter OTHER = "unittest-other";

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
    For tChannel = ..#CHANNEL, ..#OTHER {
        For tVersion = "1.0.9000", "1.0.1428" {
            Set tPkg = ##class(ZPM.Package).NameChannelVersionOpen(..#NAME, tChannel, tVersion, , .tSC)
            If $IsObject(tPkg) Do ##class(ZPM.Package).%DeleteId(tPkg.%Id())
            Do ##class(ZPM.PackageStorage).DeleteVersionDirectory(..#NAME, tChannel, tVersion)
        }
    }
}

ClassMethod Make(pChannel As %String, pVersion As %String) As %Status
{
    Set tPkg = ##class(ZPM.Package).%New()
    Set tPkg.name = ..#NAME
    Set tPkg.channel = pChannel
    Set tPkg.version = pVersion
    Set tBin = ##class(%Stream.FileBinary).%New()
    Set tBin.Filename = ##class(%File).TempFilename("tgz")
    Do tBin.Write("payload-"_pVersion)
    Set tPkg.package = tBin
    Set tMan = ##class(%Stream.FileCharacter).%New()
    Set tMan.Filename = ##class(%File).TempFilename("xml")
    Do tMan.Write("<Module><Name>"_..#NAME_"</Name><Version>"_pVersion_"</Version></Module>")
    Set tPkg.manifest = tMan
    Quit tPkg.%Save()
}

Method TestDryRunChangesNothing()
{
    Do ..Cleanup()
    Do $$$AssertStatusOK(..Make(..#CHANNEL, "1.0.9000"))
    Do $$$AssertStatusOK(..Make(..#CHANNEL, "1.0.1428"))
    Set tReport = {}.%FromJSON(##class(ZPM.Package).RemoveVersion(..#NAME, "1.0.9000", ..#CHANNEL, 1, 1, .tSC))
    Do $$$AssertStatusOK(tSC)
    Do $$$AssertEquals(tReport.found, 1, "found")
    Do $$$AssertEquals(tReport.dryRun, 1, "dry run reported")
    Do $$$AssertEquals(tReport.softDeleted, 0, "nothing soft-deleted")
    Do $$$AssertEquals(tReport.purged, 0, "nothing purged")
    Set tPkg = ##class(ZPM.Package).NameChannelVersionOpen(..#NAME, ..#CHANNEL, "1.0.9000", , .tSC)
    Do $$$AssertEquals(+tPkg.deleted, 0, "row still live")
}

Method TestSoftDeleteLeavesRowFlaggedAndNeighboursLive()
{
    Do ..Cleanup()
    Do $$$AssertStatusOK(..Make(..#CHANNEL, "1.0.9000"))
    Do $$$AssertStatusOK(..Make(..#CHANNEL, "1.0.1428"))
    Set tReport = {}.%FromJSON(##class(ZPM.Package).RemoveVersion(..#NAME, "1.0.9000", ..#CHANNEL, 0, 0, .tSC))
    Do $$$AssertStatusOK(tSC)
    Do $$$AssertEquals(tReport.softDeleted, 1, "soft-deleted")
    Do $$$AssertEquals(tReport.purged, 0, "not purged")
    Set tPkg = ##class(ZPM.Package).NameChannelVersionOpen(..#NAME, ..#CHANNEL, "1.0.9000", , .tSC)
    Do $$$AssertEquals(+tPkg.deleted, 1, "row flagged deleted")
    Set tKeep = ##class(ZPM.Package).NameChannelVersionOpen(..#NAME, ..#CHANNEL, "1.0.1428", , .tSC)
    Do $$$AssertEquals(+tKeep.deleted, 0, "other version untouched")
}

Method TestPurgeRemovesRowAndFilesAndOnlyThatChannel()
{
    Do ..Cleanup()
    Do $$$AssertStatusOK(..Make(..#CHANNEL, "1.0.9000"))
    Do $$$AssertStatusOK(..Make(..#CHANNEL, "1.0.1428"))
    Do $$$AssertStatusOK(..Make(..#OTHER, "1.0.9000"))
    Set tArchive = ##class(ZPM.PackageStorage).ArchivePath(..#NAME, ..#CHANNEL, "1.0.9000")
    Do $$$AssertTrue(##class(%File).Exists(tArchive), "archive on disk before")
    Set tReport = {}.%FromJSON(##class(ZPM.Package).RemoveVersion(..#NAME, "1.0.9000", ..#CHANNEL, 1, 0, .tSC))
    Do $$$AssertStatusOK(tSC)
    Do $$$AssertEquals(tReport.softDeleted, 1, "soft-deleted first")
    Do $$$AssertEquals(tReport.purged, 1, "purged")
    Do $$$AssertNotTrue($IsObject(##class(ZPM.Package).NameChannelVersionOpen(..#NAME, ..#CHANNEL, "1.0.9000", , .tSC)), "row gone")
    Do $$$AssertNotTrue(##class(%File).Exists(tArchive), "archive removed from disk")
    Do $$$AssertTrue($IsObject(##class(ZPM.Package).NameChannelVersionOpen(..#NAME, ..#CHANNEL, "1.0.1428", , .tSC)), "other version kept")
    Do $$$AssertTrue($IsObject(##class(ZPM.Package).NameChannelVersionOpen(..#NAME, ..#OTHER, "1.0.9000", , .tSC)), "same version in another channel kept")
}

Method TestPurgeCompletesAnEarlierSoftDelete()
{
    Do ..Cleanup()
    Do $$$AssertStatusOK(..Make(..#CHANNEL, "1.0.9000"))
    Do $$$AssertStatusOK(..Make(..#CHANNEL, "1.0.1428"))
    Do ##class(ZPM.Package).RemoveVersion(..#NAME, "1.0.9000", ..#CHANNEL, 0, 0, .tSC)
    Set tReport = {}.%FromJSON(##class(ZPM.Package).RemoveVersion(..#NAME, "1.0.9000", ..#CHANNEL, 1, 0, .tSC))
    Do $$$AssertStatusOK(tSC)
    Do $$$AssertEquals(tReport.wasDeleted, 1, "saw the earlier soft delete")
    Do $$$AssertEquals(tReport.softDeleted, 0, "no second soft delete")
    Do $$$AssertEquals(tReport.purged, 1, "purged now")
}

Method TestLatestIgnoresSoftDeletedHighestVersion()
{
    Do ..Cleanup()
    Do $$$AssertStatusOK(..Make(..#CHANNEL, "1.0.9000"))
    Do $$$AssertStatusOK(..Make(..#CHANNEL, "1.0.1428"))
    Do $$$AssertEquals(##class(ZPM.Package).VersionFind(..#NAME, "latest", 1, 1, ..#CHANNEL), "1.0.9000", "highest live version before delete")
    Do ##class(ZPM.Package).RemoveVersion(..#NAME, "1.0.9000", ..#CHANNEL, 0, 0, .tSC)
    Do $$$AssertEquals(##class(ZPM.Package).VersionFind(..#NAME, "latest", 1, 1, ..#CHANNEL), "1.0.1428", "latest skips the soft-deleted row")
}

Method TestUnknownVersionIsNotFound()
{
    Do ..Cleanup()
    Set tReport = {}.%FromJSON(##class(ZPM.Package).RemoveVersion(..#NAME, "9.9.9", ..#CHANNEL, 1, 0, .tSC))
    Do $$$AssertEquals(tReport.found, 0, "not found")
}

}
