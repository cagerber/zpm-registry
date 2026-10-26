Class ZPM.Utils
{

Parameter SSLCONFIGNAME = "zpmregistry";

ClassMethod ServerURL() As %String
{
  Set host = ""
  If '$ISOBJECT($Get(%request)) {
    Quit ""
  }
  Set tSecure = %request.Secure 
  Set host = %request.GetCgiEnv("HTTP_X_FORWARDED_HOST", %request.GetCgiEnv("SERVER_NAME"))
  Set proto = %request.GetCgiEnv("HTTP_X_FORWARDED_PROTO", $SELECT(tSecure: "https", 1: "http"))
  Set port = %request.GetCgiEnv("HTTP_X_FORWARDED_PORT", %request.GetCgiEnv("SERVER_PORT"))
  Set host = proto _ "://" _ host
  // Always emit the explicit port. %Net.URLParser.Parse defaults a missing
  // port to 0 (it does not imply http->80), so the IPM client on a localhost
  // HTTP path would otherwise download from "localhost:0" and 503.
  Set port = $ZStrip(port, "<>W")
  If port = "" {
    Set port = $Select(proto = "https": 443, 1: 80)
  }
  // A proxy sometimes puts the port in X-Forwarded-Host; append only when absent.
  Set tPortMatcher = ##class(%Regex.Matcher).%New(":[0-9]+$")
  Set tPortMatcher.Text = host
  If 'tPortMatcher.Locate() {
    Set host = host _ ":" _ port
  }
  If (%request.GetCgiEnv("HTTP_X_ORIGINAL_URI")'="") {
    Set path = $REPLACE(%request.URL, %request.Application,"",1,1)
    Set urlpart = $EXTRACT(%request.GetCgiEnv("HTTP_X_ORIGINAL_URI"),1,$FIND(%request.GetCgiEnv("HTTP_X_ORIGINAL_URI"), path) - $Length(path)-1)
    Set host = host _ $p(urlpart, "/" ,1,*-1)
  } Else {
    #; If not behind the proxy where it have to be hidden redirect from / to /registry
    If %request.GetCgiEnv("HTTP_X_FORWARDED_HOST")="" {
      Set host = host _ $p(%request.Application, "/" ,1,*-1)
    }
  }
  Return host
}

/// Trifour fork (9-373): rewrite the on-disk module.xml <Keywords> element to
/// the scalar comma-separated form the zpm 0.10.9 client accepts. The list
/// form (<Keywords><Keyword>a</Keyword>…</Keywords>) makes the client's
/// %XML.Reader.Correlate fail with #6232 ("Datatype validation failed for tag,
/// Keywords") because %IPM.Storage.Module.Keywords is a scalar %String.
/// Idempotent: already-scalar or absent <Keywords> is left as-is.
ClassMethod NormalizeKeywordsScalar(pModuleFile As %String, pKeywords As %String) As %Status
{
  Set tFile = $Get(pModuleFile)
  If (tFile = "") Return $$$OK
  If '##class(%File).Exists(tFile) Return $$$OK

  Set tStream = ##class(%Stream.FileCharacter).%New()
  Set tStream.TranslateTable = "UTF8"
  Set tStream.Filename = tFile
  Set tSC = tStream.Rewind()
  If $$$ISERR(tSC) Return tSC
  Set tText = tStream.Read(1000000)
  Do tStream.Close()

  // Find the <Keywords>…</Keywords> block (list form has <Keyword> children,
  // scalar form has inline text). Replace whichever form is present with a
  // single scalar <Keywords>…</Keywords> using the already-extracted keywords.
  Set tRegex = ##class(%Regex.Matcher).%New("<Keywords>[\s\S]*?</Keywords>")
  Set tRegex.Text = tText
  Set tReplacement = "<Keywords>" _ $ZConvert($Get(pKeywords), "O", "HTML") _ "</Keywords>"
  Set tNew = tRegex.ReplaceAll(tReplacement)
  If (tNew '= tText) {
    Set tOut = ##class(%Stream.FileCharacter).%New()
    Set tOut.TranslateTable = "UTF8"
    Set tOut.Filename = tFile
    Set tSC = tOut.Write(tNew)
    If $$$ISERR(tSC) Return tSC
    Set tSC = tOut.%Save()
    If $$$ISERR(tSC) Return tSC
    Do tOut.Close()
  }
  Return $$$OK
}

/// Reads from pStream
/// values of elements specified in xPathArray (Array)
/// returns values in xPathArray values
/// 
/// example 
///    set xPathArray("root/element")=""
///    set xPathArray("root/element2")=""
///    set tSC = ##class(ZPM.Utils).ReadXMLElements(stream, .xPathArray)
/// returns in xPathArray
///    xPathArray("root/element")=""
///    xPathArray("root/element", "text")="value"
///    xPathArray("root/elemen2t")=""
///    xPathArray("root/element2", "text")="value2"
ClassMethod ReadXMLElements(pStream As %Stream.Object, xPathArray) As %Status
{
    Try {
        Set tmpFolder = $$$FileTempDir
        Set tmpFilename = tmpFolder_"/file.xml"

        Set stream=##class(%Stream.FileCharacter).%New()
        Do stream.LinkToFile(tmpFilename)
        Set stream.TranslateTable = "UTF8"
        Do stream.CopyFrom(pStream)
        Do stream.%Save()

        Set binaryStream=##class(%Stream.FileBinary).%New()
        Do binaryStream.LinkToFile(tmpFilename)

        $$$ThrowOnError(##class(%XML.XPATH.Document).CreateFromStream(binaryStream, .xpathdoc))

        Set key = ""
        For {
            Set key = $ORDER(xPathArray(key))
            Quit:(key="")
            $$$ThrowOnError(xpathdoc.EvaluateExpression("/",key_"/text()", .tResults))
            If (tResults.Count()=0) {
                $$$ThrowOnError(xpathdoc.EvaluateExpression("/","Export/Document/"_key_"/text()", .tResults))
            }
            If (tResults.Count()>0) {
                For i=1:1:tResults.Count(){
                    Set xPathArray(key,"text") = $Get(xPathArray(key,"text"))_tResults.GetAt(1).ValueGet()
                }
            } 
        } 
        Do ##class(%File).RemoveDirectoryTree(tmpFolder)
        Return $$$OK
    } Catch ex {
        Return ex.AsStatus() 
    }
}

ClassMethod GetSSLConfiguration() As %String
{
    Set host = ..#SSLCONFIGNAME
    Return host
    Return ""
}

ClassMethod SQLsetup() As %Status
{
    Set tables = $LB("ZPM.Package","ZPM.Package_dependencies","ZPM.UpLink")
    New $NAMESPACE
    Set ns = $NAMESPACE

    Set $NAMESPACE = "%SYS"

    For i=1:1:$LISTLENGTH(tables) {
        Set sp = ##class(Security.SQLPrivileges).%New()
        Set sp.Grantable = 0
        Set sp.Grantee = "_PUBLIC"
        Set sp.Grantor = "_SYSTEM"
        Set sp.Namespace = ns
        Set sp.Privilege = "s"
        Set sp.SQLObject = "1,"_$LISTGET(tables,i)
        Do sp.%Save()
    }
    Return $$$OK
}

ClassMethod AddSSLConfiguration() As %Status
{
    Set sc = $$$OK
    Set host = ..#SSLCONFIGNAME
    New $NAMESPACE
    Set $NAMESPACE = "%SYS"
    If '##class(Security.SSLConfigs).Exists(host) {
        Set sc = ##class(Security.SSLConfigs).Create(host)
    }
    Return sc
}

}
