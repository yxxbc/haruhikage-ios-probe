module probe

go 1.27.3

require github.com/yxxbc/haruhikage-app v0.0.0

require (
	golang.org/x/mobile v0.0.0-20261011034528-197770444867 // indirect
	golang.org/x/mod v0.42.0 // indirect
	golang.org/x/sync v0.24.0 // indirect
	golang.org/x/tools v0.52.0 // indirect
	rsc.io/qr v0.2.0 // indirect
)

replace github.com/yxxbc/haruhikage-app => ../mygo-cloudmusic

tool golang.org/x/mobile/cmd/gobind
