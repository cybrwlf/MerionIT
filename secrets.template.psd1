@{
    PcsAdminPassword       = 'CHANGE_ME'   # local pcsadmin account, all companies
    TempUserPasswordBase   = 'CHANGE_ME'   # MRM only - combined with the property's 4-digit phone extension at runtime, e.g. TempUserPasswordBase + '1234'
    SingleUserTempPassword = 'CHANGE_ME'   # SingleUser.ps1 (new-employee named accounts) and MRQ named-user accounts
    MitLoanerPassword      = 'CHANGE_ME'   # MITUser.ps1 (annual MIT-event loaner account) - bump this to the current year's password before that year's event
}
