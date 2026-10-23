#get the user profile dirs
    $arrayusers= @(get-childitem 'C:\users' -exclude operator*,administrator*,TempUser*,PCSadmin*,public*,scan* -name )

    for ($iu=0; $iu -lt $arrayusers.length; $iu++) {
    $source= "C:\users\" + $arrayusers[$iu]
    #for each userprofile dir go and get the subdirs
    $array= @(Get-ChildItem $source -force -name -exclude .metadata, .ms-ad, .vec, app*, cookies, links, local*, nethood, printhood, recent, saved*, searches, sendto, start*, templates, tracing, downloads, music, contacts, ntuser*, my*, libraries, recorded*, intel*, 3d*, roam*)
		for ($i=0; $i -lt $array.length; $i++) {
		$pathsource=$source + "\" +$array[$i]
		$outputpath= "C:\MerionIT\backup\users\" +$arrayusers[$iu] + "\" + $array[$i]
		write-host "Copying $pathsource"
		copy-item $pathsource $outputpath -recurse -erroraction 'silentlycontinue'
		} 	
	}



