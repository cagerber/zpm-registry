Class ZPM.Owner
{

/// Check if user is not UnknownUser
ClassMethod IsAuth() As %Status
{
    If ($Username="UnknownUser") {
        Return $$$ERROR($$$GeneralError, "Authentification required")
    }
    Return $$$OK
}

ClassMethod IsOwner(packageName As %String, action As %String, channel As %String) As %Status
{
    Set owner = ""
    // Ownership is per (name, channel): the same module may be published into different
    // channels by different people, so a lookup that ignored the channel could block the
    // wrong publisher.
    &sql(SELECT TOP 1 owner INTO :owner FROM ZPM.Package WHERE name = :packageName AND channel = :channel ORDER BY publishTS DESC)
    If ( (owner'="") && (owner '= $Username) ){
        Return $$$ERROR($$$GeneralError, "Invalid package owner")
    }
    Return $$$OK
}

ClassMethod GetId() As %String
{
    Return $Username
}

ClassMethod SaveOwner(packageName, packageVersion, channel) As %Status
{
    Set owner = ..GetId()
    Set package = ##class(ZPM.Package).NameChannelVersionOpen(packageName, channel, packageVersion)
    Set package.owner = owner
    Return package.%Save()
}

}
