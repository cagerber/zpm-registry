/// Package Manager Registry API
Class ZPM.Registry Extends ZPM.REST.Base
{

Parameter VERSION = "1.3.7";

/// Channel assumed when a request does not name one, for compatibility with stock
/// zpm-registry clients that predate channels.
///
/// This registry historically held ONE stream of packages, and `release` is what names
/// that stream — so defaulting to it RESTORES stock behaviour rather than inventing an
/// answer: a stock client that installs `foo` keeps getting the release build, and the
/// channel it actually got is visible in the response, because every package row carries
/// its channel. A channel-aware caller always names one explicitly, so nothing is
/// ambiguous for it.
///
/// Set to "" to make channel-scoped requests fail closed instead.
Parameter DEFAULTCHANNEL = "release";

XData UrlMap [ XMLNamespace = "http://www.intersystems.com/urlmap" ]
{
<Routes>
  <!-- Server Info -->
  <Route Url="/" Method="GET" Call="GetInfo" Cors="true"/>
  <Route Url="/_ping" Method="GET" Call="Ping" Cors="true"/>

  <!-- Reset registry for debug purposes, limited access -->
  <Route Url="/_reset" Method="GET" Call="Reset" Cors="true"/>

  <!-- Swagger specs -->
  <Route Url="/_spec" Method="GET" Call="SwaggerSpec" Cors="true"/>

  <!-- All packages -->
  <Route Url="/packages/-/all" Method="GET" Call="AllPackages" Cors="true" />

  <!-- Package manifest -->
  <Route Url="/packages/:package/:version/:platformVersion/manifest" Method="GET" Call="PackageManifest" Cors="true" />
  <Route Url="/packages/:package/:version/manifest" Method="GET" Call="PackageManifest" Cors="true" />
  <!-- Package installer -->
  <Route Url="/packages/:package/:version/installer" Method="GET" Call="PackageInstaller" Cors="true" />

  <!-- Package information -->
  <Route Url="/packages/:package/?" Method="GET" Call="Package" Cors="true" />
  <!-- Package information with specified version -->
  <Route Url="/packages/:package/:version/?" Method="GET" Call="Package" Cors="true" />
  <!-- Package information with specified version and platform version -->
  <Route Url="/packages/:package/:version/:platformVersion/?" Method="GET" Call="Package" Cors="true" />
  <!-- Publish Package -->
  <Route Url="/packages" Method="POST" Call="PublishPackage" Cors="true" />
  <!-- Unpublish Package -->
  <Route Url="/packages/:package/:version" Method="Delete" Call="UnPublishPackageVersion" Cors="true" />

  <!-- Trifour admin API (9-373): token-authed; runs on the same /registry app
       so it survives the IIS Anonymous front (only the Authorization header is
       consumed there — custom X-Registry-Token headers pass through). -->
  <Route Url="/admin/status" Method="GET" Call="AdminStatus" Cors="true" />
  <Route Url="/admin/packages/:package/:version/keywords" Method="POST" Call="AdminSetKeywords" Cors="true" />
  <Route Url="/admin/packages" Method="POST" Call="AdminPublishPackage" Cors="true" />
  <Route Url="/admin/packages/:package/:version" Method="Delete" Call="AdminUnpublishPackageVersion" Cors="true" />

  <!-- Package Archive -->
  <Route Url="/download/:package/:platformVersion/:file" Method="GET" Call="GetArchive" Cors="true" />
  <!-- <Route Url="/download/:package/-/:file" Method="GET" Call="GetArchive" Cors="true" /> -->


  <!-- Temp url, update package, should be combined with "POST /packages"-->
  <Route Url="/package" Method="POST" Call="UpdatePackage" Cors="true" />


  <!-- Analytics -->
  <Route Url="/collect/:action" Method="POST" Call="CollectAnalytics" Cors="true" />

</Routes>
}

ClassMethod OnPreDispatch(pUrl As %String, pMethod As %String, ByRef pContinue As %Boolean) As %Status
{
  If ($$$lcase(pMethod)="options"),(1=$MATCH(pUrl,"^/packages/[^/]+/[^/]+/?$")),$PIECE(pUrl,"/",3)'="-" {
    Set pContinue = 0
    Return ..OptionsPackageVersion($PIECE(pUrl,"/",3),$PIECE(pUrl,"/",4))
  }
  Return ##super(pUrl, pMethod, .pContinue)
}

/// Package Manager general information
ClassMethod GetInfo() As %Status
{
  Set version = ..#VERSION
  If $System.CLS.IsMthd("%ZPM.PackageManager.Developer.Module", "NameOpen") {
    Set zpmModule = ##class(%ZPM.PackageManager.Developer.Module).NameOpen("trifour-zpm-registry")
    If $IsObject(zpmModule) {
      Set version = zpmModule.VersionString
    }
  }
  Set info = {
    "version": (version)
  }
  Return ..%ProcessResult($$$OK, info)
}

ClassMethod Ping() As %Status
{
  Set pong = {
    "message": "ping"
  }
  Quit ..%ProcessResult($$$OK, pong)
}

ClassMethod CheckDebug() As %Boolean
{
  If ('$ListFind($ListFromString($Roles), "%All")) {
    Return 0
  }
  If (%request.GetCgiEnv("HTTP_REGISTRY_DEBUG")'=$System.Util.GetEnviron("REGISTRY_DEBUG")) {
    Return 0
  }
  Return 1
}

ClassMethod Reset() As %Status
{
  If ('..CheckDebug()) {
    Return ..%ProcessResult(..#HTTP403FORBIDDEN)
  }
  Set sc = $$$OK
  Set tSC = ##class(Package).%KillExtent()
  Set sc = $$$ADDSC(sc, tSC)
  Set tSC = ##class(Package).%PurgeIndices()
  Set sc = $$$ADDSC(sc, tSC)

  Quit ..%ProcessResult(sc)
}

/// One registry hosts every channel, so any endpoint that RESOLVES or MODIFIES an
/// artefact must be told which channel it means: the same module@version can exist in
/// several channels, and a wrong answer would serve or delete another channel's build.
/// Fail closed rather than guess.
ClassMethod RequireChannel(Output channel As %String) As %Status
{
  Set channel = $ZStrip(%request.Get("channel", ""), "<>W")
  // Stock clients do not send ?channel=. Fall back to the DECLARED default (not a
  // hardcoded one) so they keep working, as long as DEFAULTCHANNEL names a channel.
  If (channel = "") { Set channel = $ZStrip(..#DEFAULTCHANNEL, "<>W") }
  If (channel = "") {
    Return $$$ERROR($$$GeneralError, "channel is required: pass ?channel=<release|develop|sprint|incubating> — one registry hosts every channel")
  }
  Return $$$OK
}

/// As RequireChannel, but for endpoints that take a JSON body (the admin ingest).
ClassMethod RequireBodyChannel(Output channel As %String) As %Status
{
  Set channel = ""
  If %request.Content.%IsDefined("channel") {
    Set channel = $ZStrip(%request.Content.%Get("channel"), "<>W")
  }
  // As RequireChannel: fall back to the declared default so a legacy publisher that
  // predates channels lands where it used to, rather than failing or guessing.
  If (channel = "") { Set channel = $ZStrip(..#DEFAULTCHANNEL, "<>W") }
  If (channel = "") {
    Return $$$ERROR($$$GeneralError, "body ""channel"" is required — one registry hosts every channel")
  }
  Return $$$OK
}

ClassMethod Package(pkg As %String = "", version As %String = "", platformVersion As %String = "", channel As %String = "") As %Status
{
  Set pkg = $$$lcase(pkg)

  // In-process callers (PublishPackage) pass the channel they already validated in the
  // JSON body; a routed request names it as a query parameter.
  If (channel = "") {
    Set tSC = ..RequireChannel(.channel)
    If $$$ISERR(tSC) { Return ..ReportHttpStatusCode(..#HTTP400BADREQUEST, tSC) }
  }

  If (version="") {
    $$$ThrowOnError(##class(ZPM.UpLink).FindPackageInAllUpLinks(pkg))
  }
  Set tIncludePrerelease = %request.Get("includePrerelease", 1)
  Set tIncludeSnapshots = %request.Get("includeSnapshots", 1)

  Set version = ##class(ZPM.Package).VersionFind(pkg, version, tIncludePrerelease, tIncludeSnapshots, channel)
  If (version = "") {
    Return ..ReportHttpStatusCode(..#HTTP404NOTFOUND)
  }
  Set package = ##class(ZPM.Package).NameChannelVersionOpen(pkg, channel, version, .tSC)
  If $$$ISERR(tSC) || ('$IsObject(package))||(package.deleted=1) {
    Return ..ReportHttpStatusCode(..#HTTP404NOTFOUND)
  }
  If package.deployed,platformVersion'="" {
    Set package = ##class(ZPM.DeployedPackage).NameVersionPlatformOpen(pkg, version, platformVersion, .tSC)
    If $$$ISERR(tSC) || ('$IsObject(package)) {
      Return ..ReportHttpStatusCode(..#HTTP404NOTFOUND)
    }
  }
  Return ..%ProcessResult($$$OK, package)
}

ClassMethod PackageManifest(pkg As %String = "", version As %String = "", platformVersion As %String = "") As %Status
{
  Set pkg = $$$lcase(pkg)
  Set tSC = ..RequireChannel(.channel)
  If $$$ISERR(tSC) { Return ..ReportHttpStatusCode(..#HTTP400BADREQUEST, tSC) }
  Set version = ##class(ZPM.Package).VersionFind(pkg, version, 1, 1, channel)
  If (version = "") {
    Return ..ReportHttpStatusCode(..#HTTP404NOTFOUND)
  }
  if 0,platformVersion'="" {
    Set package = ##class(ZPM.DeployedPackage).NameVersionPlatformOpen(pkg, version, platformVersion)
  }
  Else {
    Set package = ##class(ZPM.Package).NameChannelVersionOpen(pkg, channel, version)
  }

  If ('$IsObject(package))||('package.manifest.Size)||(package.deleted=1) {
    Return ..ReportHttpStatusCode(..#HTTP404NOTFOUND)
  }

  Set %response.ContentType = "text/xml"
  Return ..%ProcessResult($$$OK, package.manifest)
}

ClassMethod PackageInstaller(pkg As %String = "", version As %String = "") As %Status
{
  Set pkg = $$$lcase(pkg)
  Set tSC = ..RequireChannel(.channel)
  If $$$ISERR(tSC) { Return ..ReportHttpStatusCode(..#HTTP400BADREQUEST, tSC) }
  Set version = ##class(ZPM.Package).VersionFind(pkg, version, 1, 1, channel)
  If (version = "") {
    Return ..ReportHttpStatusCode(..#HTTP404NOTFOUND)
  }

  Set package = ##class(ZPM.Package).NameChannelVersionOpen(pkg, channel, version)
  If ('$IsObject(package)||(package.deleted=1)) {
    Return ..ReportHttpStatusCode(..#HTTP404NOTFOUND)
  }
  If package.installer.Size {
    Set filename = pkg_"-"_version_".xml"
    Set %response.ContentType = "text/xml"
    Do %response.SetHeader("Content-Disposition", "attachment; filename="""_filename_"""")
    Return ..%ProcessResult($$$OK, package.installer)
  }
  Return ..ReportHttpStatusCode(..#HTTP404NOTFOUND)
}

/// get available HTTP methods for /packages/:package/:version request
ClassMethod OptionsPackageVersion(pkg As %String = "", version As %String = "") As %Status
{
  Set options = "OPTIONS,GET"
  Set settingsFile = ##class(ZPM.Settings).%New()
  Set tSCAuth = ##class(ZPM.Owner).IsAuth()
  Set pkg = $$$lcase(pkg)
  Set tSC = ..RequireChannel(.channel)
  If $$$ISERR(tSC) { Return ..ReportHttpStatusCode(..#HTTP400BADREQUEST, tSC) }

  If ('##class(ZPM.Package).NameExists(pkg)) {
    Do %response.SetHeader("ALLOW",options)
    Return $$$OK
  }

  If ( ($$$lcase(version)'="all") && '##class(ZPM.Package).NameChannelVersionExists(pkg, channel, version) ) {
    // version doesn't exist in this channel
    Do %response.SetHeader("ALLOW",options)
    Return $$$OK
  }

  Set tSCOwner = ##class(ZPM.Owner).IsOwner(pkg, "delete", channel)

  If $$$ISOK(tSCAuth),$$$ISOK(tSCOwner),settingsFile.GetDeleteEnable() {
    Set options = options_",DELETE"
  }
  Do %response.SetHeader("ALLOW",options)
  Return $$$OK
}

/// Unpublish (delete) directly published package version
ClassMethod UnPublishPackageVersion(pkg As %String = "", version As %String = "") As %Status
{
  Set tSC = $$$OK
  Set tSC = ##class(ZPM.Owner).IsAuth()
  If ($$$ISERR(tSC)) {
    Return ..ReportHttpStatusCode(..#HTTP401UNAUTHORIZED, tSC)
  }
  Set tSC = ..RequireChannel(.channel)
  If $$$ISERR(tSC) { Return ..ReportHttpStatusCode(..#HTTP400BADREQUEST, tSC) }
  Set settingsFile = ##class(ZPM.Settings).%New()
  If ('settingsFile.GetDeleteEnable()) {
    Return ..ReportHttpStatusCode(..#HTTP403FORBIDDEN, $$$ERROR(5001,"Delete not allowed for this registry"))
  }
  Set pkg = $$$lcase(pkg)
  Set tSC = ##class(ZPM.Owner).IsOwner(pkg, "delete", channel)
  If ($$$ISERR(tSC)) {
    Return ..ReportHttpStatusCode(..#HTTP403FORBIDDEN, tSC)
  }
  If (version = "all") {
    If ('##class(ZPM.Package).NameExists(pkg)) {
      Return ..ReportHttpStatusCode(..#HTTP404NOTFOUND)
    }
    Return ##class(ZPM.Package).DeletePackage(pkg, channel)
  } Else {
    Set pPackage = ##class(ZPM.Package).NameChannelVersionOpen(pkg, channel, version)
    If ('$IsObject(pPackage)) {
      Return ..ReportHttpStatusCode(..#HTTP404NOTFOUND)
    }
    If (pPackage.UpLink'="") {
      // only directly published package could be deleted
      Return ..ReportHttpStatusCode(..#HTTP400BADREQUEST)
    }
    Return ##class(ZPM.Package).DeletePackageVersion(pkg, version, channel)
  }
}

/// Trifour admin API (9-373). Token from zpm-registry.yaml ``admin-token``;
/// sent as ``X-Registry-Token`` header (IIS Anonymous consumes only the
/// Authorization header, so custom headers reach IRIS untouched).
ClassMethod CheckAdminToken() As %Status
{
  Set settings = ##class(ZPM.Settings).%New()
  Set expected = ""
  If settings.Exists, settings.JSON.%IsDefined("admin-token") {
    Set expected = settings.JSON."admin-token"
  }
  If expected = "" {
    Return $$$ERROR($$$GeneralError, "admin token not configured (zpm-registry.yaml admin-token)")
  }
  Set provided = %request.GetCgiEnv("HTTP_X_REGISTRY_TOKEN")
  If provided = "" {
    Set provided = %request.Get("token")
  }
  If provided = "" {
    Return $$$ERROR($$$GeneralError, "admin token required (X-Registry-Token header)")
  }
  // hash-compare both sides: no timing signal on length or content
  If $SYSTEM.Encryption.SHA1Hash(provided) '= $SYSTEM.Encryption.SHA1Hash(expected) {
    Return $$$ERROR($$$GeneralError, "invalid admin token")
  }
  Return $$$OK
}

ClassMethod AdminStatus() As %Status
{
  Set tSC = ..CheckAdminToken()
  If $$$ISERR(tSC) Return ..ReportHttpStatusCode(..#HTTP401UNAUTHORIZED, tSC)
  Set payload = {
    "status": "ok",
    "version": (..#VERSION),
    "user": ($Username),
    "namespace": ($NAMESPACE)
  }
  Return ..%ProcessResult($$$OK, payload)
}

ClassMethod AdminPublishPackage() As %Status
{
  Set tSC = ..CheckAdminToken()
  If $$$ISERR(tSC) Return ..ReportHttpStatusCode(..#HTTP401UNAUTHORIZED, tSC)
  // Trifour fork (dep-97): ingest the ORIGINAL archive + its module.xml, given
  // separately. No unpack, no $zf tar, and package.hash is a genuine digest of
  // the uploaded .tgz. Legacy "path" (unpacked module dir) still accepted for
  // the module.xml lookup.
  Set archivePath = %request.Content.%Get("archive")
  Set manifestPath = %request.Content.%Get("manifest")
  If manifestPath = "" {
    Set src = %request.Content.%Get("path")
    If src '= "" {
      Set manifestPath = ##class(%File).NormalizeFilename("module.xml", src)
    }
  }
  If archivePath = "" {
    Return ..ReportHttpStatusCode(..#HTTP400BADREQUEST, $$$ERROR(5001,"body {""archive"": ""<tgz-path>"", ""manifest"": ""<module.xml-path>""} required"))
  }
  If manifestPath = "" {
    Return ..ReportHttpStatusCode(..#HTTP400BADREQUEST, $$$ERROR(5001,"manifest (module.xml path) required — or legacy ""path"" (unpacked dir)"))
  }
  If '##class(%File).Exists(manifestPath) {
    Return ..ReportHttpStatusCode(..#HTTP400BADREQUEST, $$$ERROR(5001,"module.xml not found: "_manifestPath))
  }
  Set tSC = ..RequireBodyChannel(.channel)
  If $$$ISERR(tSC) Return ..ReportHttpStatusCode(..#HTTP400BADREQUEST, tSC)
  Set tSC = ##class(ZPM.Package).LoadPackageFromArchive(archivePath, manifestPath, channel, "", 1, .name, .version)
  If $$$ISERR(tSC) {
    Return ..ReportHttpStatusCode(..#HTTP500INTERNALSERVERERROR, tSC)
  }
  Return ..%ProcessResult($$$OK, {"name": (name), "version": (version), "channel": (channel), "archive": (archivePath), "manifest": (manifestPath)})
}

ClassMethod AdminUnpublishPackageVersion(pkg As %String = "", version As %String = "") As %Status
{
  Set tSC = ..CheckAdminToken()
  If $$$ISERR(tSC) Return ..ReportHttpStatusCode(..#HTTP401UNAUTHORIZED, tSC)
  Set tSC = ..RequireChannel(.channel)
  If $$$ISERR(tSC) Return ..ReportHttpStatusCode(..#HTTP400BADREQUEST, tSC)
  Set settingsFile = ##class(ZPM.Settings).%New()
  If ('settingsFile.GetDeleteEnable()) {
    Return ..ReportHttpStatusCode(..#HTTP403FORBIDDEN, $$$ERROR(5001,"Delete not allowed for this registry"))
  }
  Set pkg = $$$lcase(pkg)
  Set pPackage = ##class(ZPM.Package).NameChannelVersionOpen(pkg, channel, version)
  If ('$IsObject(pPackage)) {
    Return ..ReportHttpStatusCode(..#HTTP404NOTFOUND)
  }
  Set tSC = ##class(ZPM.Package).DeletePackageVersion(pkg, version, channel)
  If tSC '= 1 {
    Return ..ReportHttpStatusCode(..#HTTP500INTERNALSERVERERROR, $$$ERROR(5001,"delete failed for "_pkg_"@"_version))
  }
  Return ..%ProcessResult($$$OK, {"deleted": (pkg _ "@" _ version), "channel": (channel)})
}

ClassMethod AdminSetKeywords(pkg As %String = "", version As %String = "") As %Status
{
  Set tSC = ..CheckAdminToken()
  If $$$ISERR(tSC) Return ..ReportHttpStatusCode(..#HTTP401UNAUTHORIZED, tSC)
  Set keywords = %request.Content.%Get("keywords")
  If keywords = "" {
    Return ..ReportHttpStatusCode(..#HTTP400BADREQUEST, $$$ERROR(5001,"body {""keywords"": ""a,b,c""} required"))
  }
  Set tSC = ..RequireChannel(.channel)
  If $$$ISERR(tSC) Return ..ReportHttpStatusCode(..#HTTP400BADREQUEST, tSC)
  Set pPackage = ##class(ZPM.Package).NameChannelVersionOpen($$$lcase(pkg), channel, version)
  If ('$IsObject(pPackage)) {
    Return ..ReportHttpStatusCode(..#HTTP404NOTFOUND)
  }
  Do pPackage.keywords.Clear()
  For i=1:1:$Length(keywords,",") {
    Set kw = $ZStrip($Piece(keywords,",",i),"<>W")
    If kw '= "" Do pPackage.keywords.Insert(kw)
  }
  Set tSC = pPackage.%Save()
  If $$$ISERR(tSC) {
    Return ..ReportHttpStatusCode(..#HTTP500INTERNALSERVERERROR, tSC)
  }
  Return ..%ProcessResult($$$OK, {"package": (pkg _ "@" _ version), "keywords": (keywords)})
}

ClassMethod PublishPackage() As %Status
{
  Try {

    Set name = %request.Content.%Get("name")
    Set version = %request.Content.%Get("version")
    Set deployed = %request.Content.%Get("deployed")
    Set platformVersion = %request.Content.%Get("platform_version")

    Set tSC = ..RequireBodyChannel(.channel)
    If ($$$ISERR(tSC)) {
      Return ..ReportHttpStatusCode(..#HTTP400BADREQUEST, tSC)
    }
    Set tSC = ##class(ZPM.Owner).IsAuth()
    If ($$$ISERR(tSC)) {
      Return ..ReportHttpStatusCode(..#HTTP401UNAUTHORIZED, tSC)
    }
    Set tSC = ##class(ZPM.Owner).IsOwner(name, "", channel)
    If ($$$ISERR(tSC)) {
      Return ..ReportHttpStatusCode(..#HTTP403FORBIDDEN, tSC)
    }
    If (##class(ZPM.Package).MarkAsDeleted(name, version, channel)) {
      Return ..ReportHttpStatusCode(..#HTTP500INTERNALSERVERERROR, $$$ERROR(5001,"This version was deleted, change version number"))
    }

    If (%request.ContentType '= ..#CONTENTTYPEJSON) {
      Return ..ReportHttpStatusCode(..#HTTP400BADREQUEST)
    }

    If ##class(ZPM.Package).NameChannelVersionExists(name, channel, version, .id) {
      Set package = ##class(ZPM.Package).%OpenId(id)
      Set package.UpLink = ""
    }
    Else {
      Set package = ##class(ZPM.Package).%New()
      Set package.channel = channel
    }

    $$$ThrowOnError(package.%JSONImport(%request.Content))
    $$$ThrowOnError(package.UpdateDescriptionFromManifest())
    If deployed {
      If ##class(ZPM.DeployedPackage).NameVersionPlatformExists(name, version, platformVersion, .id) {
        Set deployedPackage = ##class(ZPM.DeployedPackage).%OpenId(id, , .tSC)
      }
      Else {
        Set deployedPackage = ##class(ZPM.DeployedPackage).%New()
      }
      $$$ThrowOnError(deployedPackage.%JSONImport(%request.Content))
      $$$ThrowOnError(deployedPackage.manifest.CopyFrom(package.manifest))
      $$$ThrowOnError(deployedPackage.packageFromBase64(%request.Content.%Get("package",,"stream")))
      $$$ThrowOnError(deployedPackage.UpdateDescriptionFromManifest())
      $$$ThrowOnError(deployedPackage.%Save())
    }
    Else {
      $$$ThrowOnError(package.packageFromBase64(%request.Content.%Get("package",,"stream")))
    }
    $$$ThrowOnError(package.%Save())
    Do ##class(ZPM.Owner).SaveOwner(package.name, package.version, channel)
    Return ..Package(package.name, package.version, "", channel)
  } catch ex {
    Do ex.Log()
    Return ..Http500(ex)
  }
}

ClassMethod UpdatePackage() As %Status
{
  If (%request.ContentType '= ..#CONTENTTYPEJSON) {
    Return ..ReportHttpStatusCode(..#HTTP400BADREQUEST)
  }
  Return ##class(ZPM.Package).UpdatePackage(%request.Content)
}

ClassMethod GetArchive(name, platformVersion, fileName) As %Status
{
  Set version = $Piece($Piece(fileName, ".tgz", 1), name _ "-", 2, *)

  Set tSC = ..RequireChannel(.channel)
  If $$$ISERR(tSC) { Return ..ReportHttpStatusCode(..#HTTP400BADREQUEST, tSC) }
  Set version = ##class(ZPM.Package).VersionFind(name, version, 1, 1, channel)
  If (version = "") {
    Return ..ReportHttpStatusCode(..#HTTP404NOTFOUND)
  }

  set data = {
    "name": (name),
    "version": (version)
  }

  if platformVersion'="-" {
    Set package = ##class(ZPM.DeployedPackage).NameVersionPlatformOpen(name, version, platformVersion, , .tSC)
  }
  Else {
    Set package = ##class(ZPM.Package).NameChannelVersionOpen(name, channel, version, , .tSC)
  }

  If '$IsObject(package)||('package.size)||(package.deleted=1) {
    Return ..ReportHttpStatusCode(..#HTTP404NOTFOUND)
  }

  Do ##class(ZPM.Analytics.Event).SaveEvent("download", ..GetRemoteAddr(), data)
  Set token = ##class(%PopulateUtils).StringMin(16,16)
  Set ^IRIS.TempZPMRInst(token) = $ListBuild(name, version)
  Do %response.SetHeader("INSTALLTOKEN",token)

  Set tStream = package.package
  Set %response.NoCharSetConvert = 1
  Set %response.CharSet = "RAW"
  Set %response.ContentType = "application/tar+gzip"

  Return ..%ProcessResult($$$OK, tStream)
}

ClassMethod AllPackages() As %Status
{
  Set tList = []
  Set searchTerms = ""
  Try {
    Set searchTerms = [].%FromJSON(%request.Get("q"))
  } Catch ex {}
  $$$ThrowOnError(##class(ZPM.UpLink).UpdatePackagesFromAllUpLinks())

  Set manifest = %request.Get("manifest","")
  Set allVersions = %request.Get("allVersions","")
  Set owner = ##class(ZPM.Owner).GetId()
  // AllPackages is a LISTING: an absent channel means "every channel", and each row
  // carries its own, so this is a filter rather than a requirement.
  Set channel = %request.Get("channel", "")
  Set tList = ##class(ZPM.Package).GetLatest(searchTerms, manifest, allVersions, owner, channel, .tSC)

  If ($$$ISERR(tSC)) {
    Return ..ReportHttpStatusCode(..#HTTP400BADREQUEST, tSC)
  }
  Return ..%ProcessResult($$$OK, tList)
}

ClassMethod CollectAnalytics(action As %String = "") As %Status
{
  If (%request.ContentType '= ..#CONTENTTYPEJSON) {
    Return ..ReportHttpStatusCode(..#HTTP400BADREQUEST)
  }
  If (action = "") {
    Return ..ReportHttpStatusCode(..#HTTP404NOTFOUND)
  }
  Set token = %request.GetCgiEnv("HTTP_INSTALLTOKEN")
  If token'="", $Data(^IRIS.TempZPMRInst(token)) {
    Kill ^IRIS.TempZPMRInst(token)
    Return ##class(ZPM.Analytics.Event).SaveEvent(action, ..GetRemoteAddr(), %request.Content)
  }
  Return $$$ERROR(5001, "Invalid token")
}

}
