Class ZPM.Tests.KeywordNormalization Extends %UnitTest.TestCase
{

Method TestListFormBecomesScalar()
{
    Set tPath = ..WriteTemp("<Export><Document><Module><Name>x</Name><Keywords><Keyword>alpha</Keyword><Keyword>beta</Keyword></Keywords></Module></Document></Export>")
    Set tSC = ##class(ZPM.Utils).NormalizeKeywordsScalar(tPath, "alpha,beta")
    Do $$$AssertStatusOK(tSC)
    Set tText = ..ReadTemp(tPath)
    Do $$$AssertTrue(tText [ "<Keywords>alpha,beta</Keywords>", "scalar keywords written")
    Set tList = (tText [ "<Keyword>")
    Do $$$AssertTrue('tList, "list form removed")
    Do ..DeleteTemp(tPath)
}

Method TestScalarFormIsUnchanged()
{
    Set tSource = "<Export><Document><Module><Keywords>alpha,beta</Keywords></Module></Document></Export>"
    Set tPath = ..WriteTemp(tSource)
    Set tSC = ##class(ZPM.Utils).NormalizeKeywordsScalar(tPath, "alpha,beta")
    Do $$$AssertStatusOK(tSC)
    Do $$$AssertEquals(..ReadTemp(tPath), tSource, "scalar form untouched")
    Do ..DeleteTemp(tPath)
}

Method TestAbsentKeywordsIsUnchanged()
{
    Set tSource = "<Export><Document><Module><Name>x</Name></Module></Document></Export>"
    Set tPath = ..WriteTemp(tSource)
    Set tSC = ##class(ZPM.Utils).NormalizeKeywordsScalar(tPath, "alpha")
    Do $$$AssertStatusOK(tSC)
    Do $$$AssertEquals(..ReadTemp(tPath), tSource, "absent keywords untouched")
    Do ..DeleteTemp(tPath)
}

Method TestKeywordsAreHtmlEscaped()
{
    Set tPath = ..WriteTemp("<Export><Document><Module><Keywords><Keyword>a</Keyword></Keywords></Module></Document></Export>")
    Set tSC = ##class(ZPM.Utils).NormalizeKeywordsScalar(tPath, "a&b<c")
    Do $$$AssertStatusOK(tSC)
    Set tText = ..ReadTemp(tPath)
    Do $$$AssertTrue(tText [ "<Keywords>a&amp;b&lt;c</Keywords>", "escaped scalar keywords")
    Do ..DeleteTemp(tPath)
}

Method TestSecondRunIsNoOp()
{
    Set tPath = ..WriteTemp("<Export><Document><Module><Keywords><Keyword>a</Keyword></Keywords></Module></Document></Export>")
    Set tSC = ##class(ZPM.Utils).NormalizeKeywordsScalar(tPath, "a")
    Do $$$AssertStatusOK(tSC)
    Set tOnce = ..ReadTemp(tPath)
    Set tSC = ##class(ZPM.Utils).NormalizeKeywordsScalar(tPath, "a")
    Do $$$AssertStatusOK(tSC)
    Do $$$AssertEquals(..ReadTemp(tPath), tOnce, "second run unchanged")
    Do ..DeleteTemp(tPath)
}

Method TestEmptyPathIsOk()
{
    Do $$$AssertStatusOK(##class(ZPM.Utils).NormalizeKeywordsScalar("", "a"))
}

Method WriteTemp(pText As %String) As %String
{
    Set tPath = ##class(%File).TempFilename("xml")
    Set tStream = ##class(%Stream.FileCharacter).%New()
    Set tStream.Filename = tPath
    Do tStream.Write(pText)
    Do tStream.%Save()
    Do tStream.%Close()
    Quit tPath
}

Method ReadTemp(pPath As %String) As %String
{
    Set tStream = ##class(%Stream.FileCharacter).%New()
    Do tStream.LinkToFile(pPath)
    Set tText = tStream.Read(1000000)
    Do tStream.%Close()
    Quit tText
}

Method DeleteTemp(pPath As %String)
{
    Do ##class(%File).Delete(pPath)
}

}
