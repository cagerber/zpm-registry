/// Package Manager Registry API
Class ZPM.Registry Extends ZPM.REST.Base
{

Parameter VERSION = "1.3.5";

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

ClassMethod Package(pkg As %String = "", version As %String = "", platformVersion As %String = "") As %Status
{
  Set pkg = $$$lcase(pkg)

  If (version="") {
    $$$ThrowOnError(##class(ZPM.UpLink).FindPackageInAllUpLinks(pkg))
  }
  Set tIncludePrerelease = %request.Get("includePrerelease", 1)
  Set tIncludeSnapshots = %request.Get("includeSnapshots", 1)

  Set version = ##class(ZPM.Package).VersionFind(pkg, version, tIncludePrerelease, tIncludeSnapshots)
  If (version = "") {
    Return ..ReportHttpStatusCode(..#HTTP404NOTFOUND)
  }
  Set package = ##class(ZPM.Package).NameVersionOpen(pkg, version, .tSC)
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
  Set version = ##class(ZPM.Package).VersionFind(pkg, version)
  If (version = "") {
    Return ..ReportHttpStatusCode(..#HTTP404NOTFOUND)
  }
  if 0,platformVersion'="" {
    Set package = ##class(ZPM.DeployedPackage).NameVersionPlatformOpen(pkg, version, platformVersion)
  }
  Else {
    Set package = ##class(ZPM.Package).NameVersionOpen(pkg, version)
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
  Set version = ##class(ZPM.Package).VersionFind(pkg, version)
  If (version = "") {
    Return ..ReportHttpStatusCode(..#HTTP404NOTFOUND)
  }

  Set package = ##class(ZPM.Package).NameVersionOpen(pkg, version)
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

  If ('##class(ZPM.Package).NameExists(pkg)) {
    Do %response.SetHeader("ALLOW",options)
    Return $$$OK
  }

  If ( ($$$lcase(version)'="all") && '##class(ZPM.Package).NameVersionExists(pkg, version) ) {
    // version doesn't exit
    Do %response.SetHeader("ALLOW",options)
    Return $$$OK
  }

  Set tSCOwner = ##class(ZPM.Owner).IsOwner(pkg, "delete")

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
  Set settingsFile = ##class(ZPM.Settings).%New()
  If ('settingsFile.GetDeleteEnable()) {
    Return ..ReportHttpStatusCode(..#HTTP403FORBIDDEN, $$$ERROR(5001,"Delete not allowed for this registry"))
  }
  Set pkg = $$$lcase(pkg)
  Set tSC = ##class(ZPM.Owner).IsOwner(pkg, "delete")
  If ($$$ISERR(tSC)) {
    Return ..ReportHttpStatusCode(..#HTTP403FORBIDDEN, tSC)
  }
  If (version = "all") {
    If ('##class(ZPM.Package).NameExists(pkg)) {
      Return ..ReportHttpStatusCode(..#HTTP404NOTFOUND)
    }
    Return ##class(ZPM.Package).DeletePackage(pkg)
  } Else {
    Set pPackage = ##class(ZPM.Package).NameVersionOpen(pkg, version)
    If ('$IsObject(pPackage)) {
      Return ..ReportHttpStatusCode(..#HTTP404NOTFOUND)
    }
    If (pPackage.UpLink'="") {
      // only directly published package could be deleted
      Return ..ReportHttpStatusCode(..#HTTP400BADREQUEST)
    }
    Return ##class(ZPM.Package).DeletePackageVersion(pkg, version)
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
  // CSP worker processes cannot run $zf (LoadPackage re-tars via $zf), so the
  // ingest is replicated here without $zf: parse module.xml from the unpacked
  // dir, use the already-uploaded tgz as the archive stream.
  Set src = %request.Content.%Get("path")
  Set archivePath = %request.Content.%Get("archive")
  If src = "" {
    Return ..ReportHttpStatusCode(..#HTTP400BADREQUEST, $$$ERROR(5001,"body {""path"": ""<unpacked-module-dir>"", ""archive"": ""<tgz-path>""} required"))
  }
  If archivePath = "" {
    Return ..ReportHttpStatusCode(..#HTTP400BADREQUEST, $$$ERROR(5001,"archive path required (CSP process cannot run $zf tar)"))
  }
  Set moduleFile = ##class(%File).NormalizeFilename("module.xml", src)
  If '##class(%File).Exists(moduleFile) {
    Return ..ReportHttpStatusCode(..#HTTP400BADREQUEST, $$$ERROR(5001,"module.xml not found under "_src))
  }
  Set tSC = ##class(%XML.XPATH.Document).CreateFromFile(moduleFile, .tDocument)
  If $$$ISERR(tSC) Return ..ReportHttpStatusCode(..#HTTP500INTERNALSERVERERROR, tSC)
  Set tSC = tDocument.EvaluateExpression("/Export/Document/Module/Name", "text()", .tRes)
  If $$$ISERR(tSC) || '$IsObject(tRes.GetAt(1)) {
    Return ..ReportHttpStatusCode(..#HTTP400BADREQUEST, $$$ERROR(5001,"module.xml Name required"))
  }
  Set name = $$$lcase(tRes.GetAt(1).Value)
  Set tSC = tDocument.EvaluateExpression("/Export/Document/Module/Version", "text()", .tRes)
  If $$$ISERR(tSC) || '$IsObject(tRes.GetAt(1)) {
    Return ..ReportHttpStatusCode(..#HTTP400BADREQUEST, $$$ERROR(5001,"module.xml Version required"))
  }
  Set version = tRes.GetAt(1).Value
  Set description = ""
  Set tSC = tDocument.EvaluateExpression("/Export/Document/Module/Description", "text()", .tRes)
  If $$$ISERR(tSC) Return ..ReportHttpStatusCode(..#HTTP500INTERNALSERVERERROR, tSC)
  If $IsObject(tRes.GetAt(1)) Set description = tRes.GetAt(1).Value
  Set keywords = ""
  Set tSC = tDocument.EvaluateExpression("/Export/Document/Module/Keywords", "text()", .tRes)
  If $$$ISERR(tSC) Return ..ReportHttpStatusCode(..#HTTP500INTERNALSERVERERROR, tSC)
  If $IsObject(tRes.GetAt(1)) Set keywords = tRes.GetAt(1).Value
  Do ##class(ZPM.Package).DeleteExistingPackages(name, version)
  Set package = ##class(ZPM.Package).%New()
  Set package.name = name
  Set package.description = description
  Set keywords = $ZStrip(keywords,"<>W")
  If keywords '= "" {
    For i=1:1:$Length(keywords,",") {
      Set kw = $ZStrip($Piece(keywords,",",i),"<>W")
      If kw '= "" Do package.keywords.Insert(kw)
    }
  }
  Set package.version = version
  Set archive = ##class(%Stream.FileBinary).%New()
  Set archive.Filename = archivePath
  Set package.package = archive
  Set module = ##class(%Stream.FileCharacter).%New()
  Set module.Filename = moduleFile
  Set package.manifest = module
  Set package.hash = $$$lcase(##class(%File).SHA1Hash(archivePath, 1))
  Set tSC = package.%Save()
  If $$$ISERR(tSC) {
    Return ..ReportHttpStatusCode(..#HTTP500INTERNALSERVERERROR, tSC)
  }
  Return ..%ProcessResult($$$OK, {"name": (name), "version": (version), "keywords": (keywords)})
}

ClassMethod AdminUnpublishPackageVersion(pkg As %String = "", version As %String = "") As %Status
{
  Set tSC = ..CheckAdminToken()
  If $$$ISERR(tSC) Return ..ReportHttpStatusCode(..#HTTP401UNAUTHORIZED, tSC)
  Set settingsFile = ##class(ZPM.Settings).%New()
  If ('settingsFile.GetDeleteEnable()) {
    Return ..ReportHttpStatusCode(..#HTTP403FORBIDDEN, $$$ERROR(5001,"Delete not allowed for this registry"))
  }
  Set pkg = $$$lcase(pkg)
  Set pPackage = ##class(ZPM.Package).NameVersionOpen(pkg, version)
  If ('$IsObject(pPackage)) {
    Return ..ReportHttpStatusCode(..#HTTP404NOTFOUND)
  }
  Set tSC = ##class(ZPM.Package).DeletePackageVersion(pkg, version)
  If tSC '= 1 {
    Return ..ReportHttpStatusCode(..#HTTP500INTERNALSERVERERROR, $$$ERROR(5001,"delete failed for "_pkg_"@"_version))
  }
  Return ..%ProcessResult($$$OK, {"deleted": (pkg _ "@" _ version)})
}

ClassMethod AdminSetKeywords(pkg As %String = "", version As %String = "") As %Status
{
  Set tSC = ..CheckAdminToken()
  If $$$ISERR(tSC) Return ..ReportHttpStatusCode(..#HTTP401UNAUTHORIZED, tSC)
  Set keywords = %request.Content.%Get("keywords")
  If keywords = "" {
    Return ..ReportHttpStatusCode(..#HTTP400BADREQUEST, $$$ERROR(5001,"body {""keywords"": ""a,b,c""} required"))
  }
  Set pPackage = ##class(ZPM.Package).NameVersionOpen($$$lcase(pkg), version)
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

    Set tSC = ##class(ZPM.Owner).IsAuth()
    If ($$$ISERR(tSC)) {
      Return ..ReportHttpStatusCode(..#HTTP401UNAUTHORIZED, tSC)
    }
    Set tSC = ##class(ZPM.Owner).IsOwner(name)
    If ($$$ISERR(tSC)) {
      Return ..ReportHttpStatusCode(..#HTTP403FORBIDDEN, tSC)
    }
    If (##class(ZPM.Package).MarkAsDeleted(name, version)) {
      Return ..ReportHttpStatusCode(..#HTTP500INTERNALSERVERERROR, $$$ERROR(5001,"This version was deleted, change version number"))
    }

    If (%request.ContentType '= ..#CONTENTTYPEJSON) {
      Return ..ReportHttpStatusCode(..#HTTP400BADREQUEST)
    }

    If ##class(ZPM.Package).NameVersionExists(name, version, .id) {
      Set package = ##class(ZPM.Package).%OpenId(id)
      Set package.UpLink = ""
    }
    Else {
      Set package = ##class(ZPM.Package).%New()
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
    Do ##class(ZPM.Owner).SaveOwner(package.name, package.version)
    Return ..Package(package.name, package.version)
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

  Set version = ##class(ZPM.Package).VersionFind(name, version)
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
    Set package = ##class(ZPM.Package).NameVersionOpen(name, version, , .tSC)
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
  Set tList = ##class(ZPM.Package).GetLatest(searchTerms, manifest, allVersions, owner, .tSC)

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
