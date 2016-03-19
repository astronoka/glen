# glen

Go environment manager


# Installation

```
$ git clone https://github.com/astronoka/glen.git ~/.glen
$ ln -s ~/.glen/glen.sh ~/bin/glen
$ glen version
0.2.0
```


# Usage

```
Usage: glen <cmd>

Commands:

version                         Print glen version
help                            Output help text
install <version>               Install the version passed (ex: go1.5.3)
uninstall <version>             Delete the install for <version>
use <version>                   Activate specified <version>
list                            List installed versions
tags                            List available versions (tags)

env list                        List environments
env create <envname> <version>  Create environment
env delete <envname>            Delete environment
env use    <envname>            Activate environment

vendor init <version>           Initialize current directory as workspace
vendor use                      Activate current directory as workspace

tools                           Install develop tools (goimports,gorename...)
```

## Basic mode

```bash
[astronoka ~]$ glen use go1.6
(glen:go1.6)[astronoka ~]$ go env
...
GOPATH="/Users/astronoka/.glen/installed/go1.6/glen"
...
GOROOT="/Users/astronoka/.glen/installed/go1.6"
...
```

## Env mode

```bash
[astronoka ~]$ glen env list
[astronoka ~]$ glen env create awesomeapp go1.6
[astronoka ~]$ glen env list
awesomeapp
[astronoka ~]$ glen env use awesomeapp
(awesomeapp:go1.6)[astronoka ~]$ go env
...
GOPATH="/Users/astronoka/.glen/env/awesomeapp"
...
GOROOT="/Users/astronoka/.glen/installed/go1.6"
...
(awesomeapp:go1.6)[astronoka ~]$ exit
[astronoka ~]$ glen env delete awesomeapp
[astronoka ~]$ glen env list
```

## Vendor mode

```bash
[astronoka ~]$ mkdir amazingapp
[astronoka ~]$ cd amazingapp/
[astronoka amazingapp]$ glen vendor init go1.6
create vendor directory
create glenrc
successfully initialized: /Users/astronoka/amazingapp
[astronoka amazingapp]$ ls
glenrc vendor
[astronoka amazingapp]$ glen vendor use
(amazingapp:go1.6)[astronoka amazingapp]$ go env
...
GOPATH="/Users/astronoka/amazingapp/vendor"
...
GOROOT="/Users/astronoka/.glen/installed/go1.6"
...
```

## Install develop tools

```bash
(glen:go1.6)[astronoka ~]$ glen tools
go get github.com/nsf/gocode into /Users/astronoka/.glen/installed/go1.6/glen
go get github.com/alecthomas/gometalinter into /Users/astronoka/.glen/installed/go1.6/glen
go get golang.org/x/tools/cmd/goimports into /Users/astronoka/.glen/installed/go1.6/glen
go get github.com/rogpeppe/godef into /Users/astronoka/.glen/installed/go1.6/glen
go get golang.org/x/tools/cmd/oracle into /Users/astronoka/.glen/installed/go1.6/glen
go get golang.org/x/tools/cmd/gorename into /Users/astronoka/.glen/installed/go1.6/glen
go get github.com/golang/lint/golint into /Users/astronoka/.glen/installed/go1.6/glen
go get github.com/kisielk/errcheck into /Users/astronoka/.glen/installed/go1.6/glen
go get github.com/jstemmer/gotags into /Users/astronoka/.glen/installed/go1.6/glen
```


# Inspired

- https://github.com/isaacs/nave
- https://github.com/pypa/virtualenv
- http://www.allmovie.com/movie/v19952
