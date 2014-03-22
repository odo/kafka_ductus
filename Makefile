SHELL = zsh -i

all:
	./rebar get-deps compile

completion:
	@print -rl 'Zsh completions are loaded from your fpath directories. Your current fpath is:' \
		$$fpath
	@eval 'dst=$$fpath[1] ; vared -p "Install _krepl to: " -c dst ; cp priv/zsh-completion.sh $$dst/_krepl' \
		&& zsh -i && echo "Done!" \
		|| echo 'Failed; does the directory exist? Did you forget sudo?'
