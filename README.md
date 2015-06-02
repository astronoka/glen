glen
====

Go environment manager

Installation
====

```
$ git clone https://github.com/astronoka/glen.git ~/.glen
$ ln -s ~/.glen/glen.sh ~/bin/glen
$ glen version
0.1.0
```

Usage
====

```
Usage: glen <cmd>

Commands:

version                         Print glen version
help                            Output help text
install <version>               Install the version passed (ex: go1.4.2)
uninstall <version>             Delete the install for <version>
list                            List installed versions
available                       List available versions (tags)
env list                        List environments
env create <envname> <version>  Create environment
env delete <envname>            Delete environment
env use <envname>               Activate environment
workon <envname>                Activate environment
```
