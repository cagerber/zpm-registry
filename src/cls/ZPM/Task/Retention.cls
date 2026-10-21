/// Nightly registry retention: keep the newest <property>KeepLatest</property> live versions per
/// (name, channel), soft-delete older ones, then hard-purge them with
/// <method>ZPM.Package.PurgeDeleted</method> so the bytes really leave the database.
/// <p>The server cannot see the deploy estate or the package cache, so the client
/// (ods-release <code>ipm_registry_cli.py remove --write-task-inputs</code>) maintains two globals:
/// <ul>
/// <li><code>^ZPM.RetentionPins(name, channel, version) = tag</code>: versions an open deploy
/// transaction or a site's latest plan uses. Never touched.</li>
/// <li><code>^ZPM.RetentionAllow(name, channel, version) = cached tgz path</code>: versions the
/// client verified it can re-upload. The task acts ONLY on these.</li>
/// <li><code>^ZPM.RetentionAllow</code> top node = <code>$ZTIMESTAMP</code> written; inputs older than
/// <property>MaxInputAgeHours</property> are refused.</li>
/// </ul>
/// Each run logs to <code>^ZPM.RetentionLog(runId)</code> (summary) and <code>(runId, n)</code> (one line per version).
Class ZPM.Task.Retention Extends %SYS.Task.Definition
{

Parameter TaskName = "ZPM Registry Retention";

/// Newest live versions kept per (name, channel).
Property KeepLatest As %Integer [ InitialExpression = 3 ];

/// Most versions soft-deleted + purged per run (0 = no cap). Bounds journal growth.
Property Cap As %Integer [ InitialExpression = 300 ];

/// Report what would happen; change nothing.
Property DryRun As %Boolean [ InitialExpression = 0 ];

/// Refuse to act when the client inputs are older than this.
Property MaxInputAgeHours As %Integer [ InitialExpression = 48 ];

Method OnTask() As %Status
{
  Set runId = $Increment(^ZPM.RetentionLog)
  Set ^ZPM.RetentionLog(runId) = $ListBuild($ZDateTime($Horolog, 3), "started", ..KeepLatest, ..Cap, ..DryRun)
  Set sc = ..Run(runId, .summary)
  Set ^ZPM.RetentionLog(runId) = $ListBuild($ZDateTime($Horolog, 3), $Select($$$ISOK(sc): "ok", 1: "error: "_$System.Status.GetErrorText(sc)), ..KeepLatest, ..Cap, ..DryRun, $Get(summary("candidates")), $Get(summary("deleted")), $Get(summary("purged")), $Get(summary("bytes")), $Get(summary("skippedPinned")), $Get(summary("skippedNotAllowed")))
  Return sc
}

/// One line in this run's log.
Method Log(runId As %Integer, msg As %String) [ Private ]
{
  Set ^ZPM.RetentionLog(runId, $Increment(^ZPM.RetentionLog(runId, 0))) = $ZDateTime($Horolog, 3)_" "_msg
}

Method Run(runId As %Integer, Output summary) As %Status [ Private ]
{
  Kill summary
  Set (summary("candidates"), summary("deleted"), summary("purged"), summary("bytes"), summary("skippedPinned"), summary("skippedNotAllowed")) = 0
  If ..KeepLatest < 1 Return $$$ERROR($$$GeneralError, "KeepLatest must be >= 1")
  Set written = $Get(^ZPM.RetentionAllow)
  If written = "" Return $$$ERROR($$$GeneralError, "no client inputs: ^ZPM.RetentionAllow is empty")
  Set ageSec = ($Piece($ZTimeStamp, ",") - $Piece(written, ",")) * 86400 + ($Piece($ZTimeStamp, ",", 2) - $Piece(written, ",", 2))
  If ageSec > (..MaxInputAgeHours * 3600) Return $$$ERROR($$$GeneralError, "client inputs are "_(ageSec\3600)_"h old (max "_..MaxInputAgeHours_"h)")
  Set sql = "SELECT name, channel, version, deleted FROM ZPM.Package WHERE UpLink IS NULL ORDER BY name, channel, versionMajor DESC, versionMinor DESC, versionPatch DESC, versionPrerelease"
  Set rs = ##class(%SQL.Statement).%ExecDirect(, sql)
  If rs.%SQLCODE < 0 Return $$$ERROR($$$SQLError, rs.%SQLCODE, rs.%Message)
  // Prerelease ordering: SQL sorts "" (a release) first among equal major.minor.patch,
  // which is the semver order (1.0.0 > 1.0.0-rc1).
  Set group = "", rank = 0, n = 0
  While rs.%Next() {
    Set name = rs.name, ch = rs.channel, ver = rs.version
    If (name_"|"_ch) '= group Set group = name_"|"_ch, rank = 0
    Set live = (rs.deleted '= 1)
    Set:live rank = rank + 1
    // newest KeepLatest LIVE versions are never candidates; already soft-deleted rows are
    // candidates for purge only.
    Continue:live&&(rank <= ..KeepLatest)
    If $Data(^ZPM.RetentionPins(name, ch, ver)) {
      Set summary("skippedPinned") = summary("skippedPinned") + 1
      Continue
    }
    If '$Data(^ZPM.RetentionAllow(name, ch, ver)) {
      Set summary("skippedNotAllowed") = summary("skippedNotAllowed") + 1
      Continue
    }
    If (..Cap > 0) && (n >= ..Cap) {
      Quit
    }
    Set n = n + 1, summary("candidates") = n
    If ..DryRun {
      Do ..Log(runId, "dry-run would remove "_name_"@"_ver_" ("_ch_")")
      Continue
    }
    If live {
      Set sc = ##class(ZPM.Package).DeletePackageVersion(name, ver, ch)
      If $$$ISERR(sc) {
        Do ..Log(runId, "FAIL soft-delete "_name_"@"_ver_": "_$System.Status.GetErrorText(sc))
        Continue
      }
      Set summary("deleted") = summary("deleted") + 1
    }
    Set report = {}.%FromJSON(##class(ZPM.Package).PurgeDeleted(0, 1, name, ch, .psc, ver))
    If $$$ISERR(psc) {
      Do ..Log(runId, "FAIL purge "_name_"@"_ver_": "_$System.Status.GetErrorText(psc))
      Continue
    }
    Set summary("purged") = summary("purged") + report.purged, summary("bytes") = summary("bytes") + report.bytes
    Do ..Log(runId, "removed "_name_"@"_ver_" ("_ch_") bytes="_report.bytes)
  }
  Return $$$OK
}

/// Replace both client input globals in one call. <var>pJson</var>:
/// <code>{"pins":[[name,channel,version,tag],...],"allow":[[name,channel,version,path],...]}</code>.
/// Returns <code>{"pins":n,"allow":n,"writtenAt":$ZTS}</code>.
ClassMethod SetInputs(pJson As %String) As %String
{
  Set in = {}.%FromJSON(pJson)
  Kill ^ZPM.RetentionPins, ^ZPM.RetentionAllow
  Set (np, na) = 0
  Set it = in.pins.%GetIterator()
  While it.%GetNext(, .row) {
    Set ^ZPM.RetentionPins(row.%Get(0), row.%Get(1), row.%Get(2)) = row.%Get(3), np = np + 1
  }
  Set it = in.allow.%GetIterator()
  While it.%GetNext(, .row) {
    Set ^ZPM.RetentionAllow(row.%Get(0), row.%Get(1), row.%Get(2)) = row.%Get(3), na = na + 1
  }
  Set ^ZPM.RetentionAllow = $ZTimeStamp
  Return {"pins":(np), "allow":(na), "writtenAt":($ZTimeStamp)}.%ToJSON()
}

/// Create or update the nightly task (idempotent). Called from module.xml on install/upgrade.
/// Runs in the namespace the module is installed in, daily at 02:00 server time.
ClassMethod Install(pNamespace As %String = {$Namespace}) As %Status
{
  Set tid = ""
  &sql(SELECT ID INTO :tid FROM %SYS.Task WHERE TaskClass = 'ZPM.Task.Retention' AND NameSpace = :pNamespace)
  Set task = $Select(tid '= "": ##class(%SYS.Task).%OpenId(tid), 1: ##class(%SYS.Task).%New())
  If '$IsObject(task) Return $$$ERROR($$$GeneralError, "cannot open/create %SYS.Task")
  If tid = "" {
    // settings are only seeded on create, so an operator's tuning survives an upgrade
    Set def = ..%New()
    Set sc = task.AssignSettings(def)
    Return:$$$ISERR(sc) sc
  }
  Set task.Name = ..#TaskName_" ("_pNamespace_")"
  Set task.Description = "Keep newest N per (name, channel); soft-delete + hard-purge allow-listed, unpinned older versions"
  Set task.NameSpace = pNamespace
  Set task.TaskClass = "ZPM.Task.Retention"
  Set task.RunAsUser = "_SYSTEM"
  Set task.TimePeriod = 0, task.TimePeriodEvery = 1, task.DailyFrequency = 0, task.DailyStartTime = 7200
  Set task.Suspended = 0
  Set sc = task.%Save()
  Return sc
}

}
