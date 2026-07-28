@{
    PcsAdminPassword       = 'CHANGE_ME'   # local pcsadmin account, all companies
    TempUserPasswordBase   = 'CHANGE_ME'   # MRM only - combined with the property's 4-digit phone extension at runtime, e.g. TempUserPasswordBase + '1234'
    SingleUserTempPassword = 'CHANGE_ME'   # MRQ named-user accounts (DefaultAccounts.ps1) - SingleUser.ps1 prompts for its own password and does not use this
    MitLoanerPassword      = 'CHANGE_ME'   # MITUser.ps1 (annual MIT-event loaner account) - bump this to the current year's password before that year's event
}
