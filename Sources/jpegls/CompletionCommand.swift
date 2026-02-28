import ArgumentParser
import Foundation

/// Generate shell completion scripts
struct Completion: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "completion",
        abstract: "Generate shell completion scripts",
        discussion: """
        Generate shell completion scripts for bash, zsh, or fish shells.
        
        Installation instructions:
        
        Bash:
          jpegls completion bash > /etc/bash_completion.d/jpegls
          # or for user installation:
          jpegls completion bash > ~/.local/share/bash-completion/completions/jpegls
        
        Zsh:
          jpegls completion zsh > /usr/local/share/zsh/site-functions/_jpegls
          # or for user installation:
          jpegls completion zsh > ~/.zfunc/_jpegls
          # Then add to ~/.zshrc: fpath=(~/.zfunc $fpath)
        
        Fish:
          jpegls completion fish > ~/.config/fish/completions/jpegls.fish
        """
    )
    
    @Argument(help: "Shell type: bash, zsh, or fish")
    var shell: String
    
    mutating func validate() throws {
        let validShells = ["bash", "zsh", "fish"]
        guard validShells.contains(shell.lowercased()) else {
            throw ValidationError("Invalid shell '\(shell)'. Must be one of: \(validShells.joined(separator: ", "))")
        }
    }
    
    func run() throws {
        let script: String
        
        switch shell.lowercased() {
        case "bash":
            script = generateBashCompletion()
        case "zsh":
            script = generateZshCompletion()
        case "fish":
            script = generateFishCompletion()
        default:
            throw ValidationError("Unsupported shell: \(shell)")
        }
        
        print(script)
    }
    
    private func generateBashCompletion() -> String {
        return """
        # bash completion for jpegls
        
        _jpegls_completion() {
            local cur prev words cword
            _init_completion || return
        
            local commands="encode decode info verify batch compare completion"
            local global_opts="--version --help -h"
        
            # Complete subcommands
            if [[ $cword -eq 1 ]]; then
                COMPREPLY=($(compgen -W "$commands $global_opts" -- "$cur"))
                return
            fi
        
            # Get the subcommand
            local subcommand="${words[1]}"
        
            case "$subcommand" in
                encode)
                    local opts="--width -w --height -h --bits-per-sample -b --components -c --near --interleave --color-transform --colour-transform --t1 --t2 --t3 --reset --optimise --optimize --no-colour --no-color --verbose -v --quiet -q --help"
                    COMPREPLY=($(compgen -W "$opts" -- "$cur"))
                    # Complete file paths
                    if [[ ! $cur = -* ]]; then
                        COMPREPLY+=($(compgen -f -- "$cur"))
                    fi
                    ;;
                decode)
                    local opts="--format --no-colour --no-color --verbose -v --quiet -q --help"
                    COMPREPLY=($(compgen -W "$opts" -- "$cur"))
                    # Complete .jls files
                    if [[ ! $cur = -* ]]; then
                        COMPREPLY+=($(compgen -f -X '!*.jls' -- "$cur"))
                    fi
                    ;;
                info)
                    local opts="--json --no-colour --no-color --quiet -q --help"
                    COMPREPLY=($(compgen -W "$opts" -- "$cur"))
                    # Complete .jls files
                    if [[ ! $cur = -* ]]; then
                        COMPREPLY+=($(compgen -f -X '!*.jls' -- "$cur"))
                    fi
                    ;;
                verify)
                    local opts="--no-colour --no-color --verbose -v --quiet -q --help"
                    COMPREPLY=($(compgen -W "$opts" -- "$cur"))
                    # Complete .jls files
                    if [[ ! $cur = -* ]]; then
                        COMPREPLY+=($(compgen -f -X '!*.jls' -- "$cur"))
                    fi
                    ;;
                batch)
                    local opts="--output-dir -o --width -w --height -h --bits-per-sample -b --components -c --near --interleave --color-transform --colour-transform --parallelism -p --summarise --summarize --no-colour --no-color --verbose -v --quiet -q --fail-fast --help"
                    # First positional argument is operation
                    if [[ $cword -eq 2 ]]; then
                        COMPREPLY=($(compgen -W "encode decode info verify" -- "$cur"))
                    elif [[ ! $cur = -* ]]; then
                        # File/pattern completion
                        COMPREPLY=($(compgen -f -- "$cur"))
                    else
                        COMPREPLY=($(compgen -W "$opts" -- "$cur"))
                    fi
                    ;;
                compare)
                    local opts="--near --json --no-colour --no-color --verbose -v --quiet -q --help"
                    COMPREPLY=($(compgen -W "$opts" -- "$cur"))
                    # Complete .jls/.pgm/.ppm files
                    if [[ ! $cur = -* ]]; then
                        COMPREPLY+=($(compgen -f -- "$cur"))
                    fi
                    ;;
                completion)
                    local opts="bash zsh fish --help"
                    COMPREPLY=($(compgen -W "$opts" -- "$cur"))
                    ;;
                *)
                    COMPREPLY=()
                    ;;
            esac
        }
        
        complete -F _jpegls_completion jpegls
        """
    }
    
    private func generateZshCompletion() -> String {
        return """
        #compdef jpegls
        
        _jpegls() {
            local context state state_descr line
            typeset -A opt_args
        
            _arguments -C \\
                '1: :->command' \\
                '*:: :->args'
        
            case $state in
                command)
                    _arguments '1:command:(encode decode info verify batch compare completion --version --help)'
                    ;;
                args)
                    case $words[1] in
                        encode)
                            _arguments \\
                                '1:input-file:_files' \\
                                '2:output-file:_files' \\
                                '(-w --width)'{-w,--width}'[Image width]:width:' \\
                                '(-h --height)'{-h,--height}'[Image height]:height:' \\
                                '(-b --bits-per-sample)'{-b,--bits-per-sample}'[Bits per sample]:bits:(8 12 16)' \\
                                '(-c --components)'{-c,--components}'[Component count]:components:(1 3)' \\
                                '--near[NEAR parameter]:near:(0 1 2 3 4 5)' \\
                                '--interleave[Interleave mode]:mode:(none line sample)' \\
                                '--color-transform[Colour transform (American spelling)]:transform:(none hp1 hp2 hp3)' \\
                                '--colour-transform[Colour transform (British spelling)]:transform:(none hp1 hp2 hp3)' \\
                                '--t1[Custom T1 threshold]:t1:' \\
                                '--t2[Custom T2 threshold]:t2:' \\
                                '--t3[Custom T3 threshold]:t3:' \\
                                '--reset[Custom RESET value]:reset:' \\
                                '--optimise[Embed preset parameters (British spelling)]' \\
                                '--optimize[Embed preset parameters (American spelling)]' \\
                                '--no-colour[Disable ANSI colour (British spelling)]' \\
                                '--no-color[Disable ANSI colour (American spelling)]' \\
                                '(-v --verbose)'{-v,--verbose}'[Verbose output]' \\
                                '(-q --quiet)'{-q,--quiet}'[Quiet mode]'
                            ;;
                        decode)
                            _arguments \\
                                '1:input-file:_files -g "*.jls"' \\
                                '2:output-file:_files' \\
                                '--format[Output format]:format:(raw pgm ppm png tiff)' \\
                                '--no-colour[Disable ANSI colour (British spelling)]' \\
                                '--no-color[Disable ANSI colour (American spelling)]' \\
                                '(-v --verbose)'{-v,--verbose}'[Verbose output]' \\
                                '(-q --quiet)'{-q,--quiet}'[Quiet mode]'
                            ;;
                        info)
                            _arguments \\
                                '1:input-file:_files -g "*.jls"' \\
                                '--json[JSON output]' \\
                                '--no-colour[Disable ANSI colour (British spelling)]' \\
                                '--no-color[Disable ANSI colour (American spelling)]' \\
                                '(-q --quiet)'{-q,--quiet}'[Quiet mode]'
                            ;;
                        verify)
                            _arguments \\
                                '1:input-file:_files -g "*.jls"' \\
                                '--no-colour[Disable ANSI colour (British spelling)]' \\
                                '--no-color[Disable ANSI colour (American spelling)]' \\
                                '(-v --verbose)'{-v,--verbose}'[Verbose output]' \\
                                '(-q --quiet)'{-q,--quiet}'[Quiet mode]'
                            ;;
                        batch)
                            _arguments \\
                                '1:operation:(encode decode info verify)' \\
                                '2:pattern:_files' \\
                                '(-o --output-dir)'{-o,--output-dir}'[Output directory]:dir:_directories' \\
                                '(-w --width)'{-w,--width}'[Image width]:width:' \\
                                '(-h --height)'{-h,--height}'[Image height]:height:' \\
                                '(-b --bits-per-sample)'{-b,--bits-per-sample}'[Bits per sample]:bits:(8 12 16)' \\
                                '(-c --components)'{-c,--components}'[Component count]:components:(1 3)' \\
                                '--near[NEAR parameter]:near:(0 1 2 3 4 5)' \\
                                '--interleave[Interleave mode]:mode:(none line sample)' \\
                                '--color-transform[Colour transform (American spelling)]:transform:(none hp1 hp2 hp3)' \\
                                '--colour-transform[Colour transform (British spelling)]:transform:(none hp1 hp2 hp3)' \\
                                '(-p --parallelism)'{-p,--parallelism}'[Parallelism]:count:' \\
                                '--summarise[Print summary (British spelling)]' \\
                                '--summarize[Print summary (American spelling)]' \\
                                '--no-colour[Disable ANSI colour (British spelling)]' \\
                                '--no-color[Disable ANSI colour (American spelling)]' \\
                                '(-v --verbose)'{-v,--verbose}'[Verbose output]' \\
                                '(-q --quiet)'{-q,--quiet}'[Quiet mode]' \\
                                '--fail-fast[Stop on first error]'
                            ;;
                        compare)
                            _arguments \\
                                '1:first-file:_files' \\
                                '2:second-file:_files' \\
                                '--near[Pixel error tolerance]:near:(0 1 2 3 4 5)' \\
                                '--json[JSON output]' \\
                                '--no-colour[Disable ANSI colour (British spelling)]' \\
                                '--no-color[Disable ANSI colour (American spelling)]' \\
                                '(-v --verbose)'{-v,--verbose}'[Verbose output]' \\
                                '(-q --quiet)'{-q,--quiet}'[Quiet mode]'
                            ;;
                        completion)
                            _arguments '1:shell:(bash zsh fish)'
                            ;;
                    esac
                    ;;
            esac
        }
        
        _jpegls "$@"
        """
    }
    
    private func generateFishCompletion() -> String {
        return """
        # fish completion for jpegls
        
        # Global options
        complete -c jpegls -l version -d "Show version"
        complete -c jpegls -s h -l help -d "Show help"
        
        # Subcommands
        complete -c jpegls -f -n "__fish_use_subcommand" -a encode -d "Encode image to JPEG-LS"
        complete -c jpegls -f -n "__fish_use_subcommand" -a decode -d "Decode JPEG-LS file"
        complete -c jpegls -f -n "__fish_use_subcommand" -a info -d "Display file information"
        complete -c jpegls -f -n "__fish_use_subcommand" -a verify -d "Verify file integrity"
        complete -c jpegls -f -n "__fish_use_subcommand" -a batch -d "Batch process files"
        complete -c jpegls -f -n "__fish_use_subcommand" -a compare -d "Compare two image files"
        complete -c jpegls -f -n "__fish_use_subcommand" -a completion -d "Generate shell completions"
        
        # encode command
        complete -c jpegls -f -n "__fish_seen_subcommand_from encode" -s w -l width -d "Image width" -r
        complete -c jpegls -f -n "__fish_seen_subcommand_from encode" -s h -l height -d "Image height" -r
        complete -c jpegls -f -n "__fish_seen_subcommand_from encode" -s b -l bits-per-sample -d "Bits per sample" -r
        complete -c jpegls -f -n "__fish_seen_subcommand_from encode" -s c -l components -d "Component count" -r
        complete -c jpegls -f -n "__fish_seen_subcommand_from encode" -l near -d "NEAR parameter" -r
        complete -c jpegls -f -n "__fish_seen_subcommand_from encode" -l interleave -d "Interleave mode" -r -a "none line sample"
        complete -c jpegls -f -n "__fish_seen_subcommand_from encode" -l color-transform -d "Colour transform (American spelling)" -r -a "none hp1 hp2 hp3"
        complete -c jpegls -f -n "__fish_seen_subcommand_from encode" -l colour-transform -d "Colour transform (British spelling)" -r -a "none hp1 hp2 hp3"
        complete -c jpegls -f -n "__fish_seen_subcommand_from encode" -l t1 -d "Custom T1 threshold" -r
        complete -c jpegls -f -n "__fish_seen_subcommand_from encode" -l t2 -d "Custom T2 threshold" -r
        complete -c jpegls -f -n "__fish_seen_subcommand_from encode" -l t3 -d "Custom T3 threshold" -r
        complete -c jpegls -f -n "__fish_seen_subcommand_from encode" -l reset -d "Custom RESET value" -r
        complete -c jpegls -f -n "__fish_seen_subcommand_from encode" -l optimise -d "Embed preset parameters (British spelling)"
        complete -c jpegls -f -n "__fish_seen_subcommand_from encode" -l optimize -d "Embed preset parameters (American spelling)"
        complete -c jpegls -f -n "__fish_seen_subcommand_from encode" -l no-colour -d "Disable ANSI colour (British spelling)"
        complete -c jpegls -f -n "__fish_seen_subcommand_from encode" -l no-color -d "Disable ANSI colour (American spelling)"
        complete -c jpegls -f -n "__fish_seen_subcommand_from encode" -s v -l verbose -d "Verbose output"
        complete -c jpegls -f -n "__fish_seen_subcommand_from encode" -s q -l quiet -d "Quiet mode"
        
        # decode command
        complete -c jpegls -f -n "__fish_seen_subcommand_from decode" -l format -d "Output format" -r -a "raw pgm ppm png tiff"
        complete -c jpegls -f -n "__fish_seen_subcommand_from decode" -l no-colour -d "Disable ANSI colour (British spelling)"
        complete -c jpegls -f -n "__fish_seen_subcommand_from decode" -l no-color -d "Disable ANSI colour (American spelling)"
        complete -c jpegls -f -n "__fish_seen_subcommand_from decode" -s v -l verbose -d "Verbose output"
        complete -c jpegls -f -n "__fish_seen_subcommand_from decode" -s q -l quiet -d "Quiet mode"
        
        # info command
        complete -c jpegls -f -n "__fish_seen_subcommand_from info" -l json -d "JSON output"
        complete -c jpegls -f -n "__fish_seen_subcommand_from info" -l no-colour -d "Disable ANSI colour (British spelling)"
        complete -c jpegls -f -n "__fish_seen_subcommand_from info" -l no-color -d "Disable ANSI colour (American spelling)"
        complete -c jpegls -f -n "__fish_seen_subcommand_from info" -s q -l quiet -d "Quiet mode"
        
        # verify command
        complete -c jpegls -f -n "__fish_seen_subcommand_from verify" -l no-colour -d "Disable ANSI colour (British spelling)"
        complete -c jpegls -f -n "__fish_seen_subcommand_from verify" -l no-color -d "Disable ANSI colour (American spelling)"
        complete -c jpegls -f -n "__fish_seen_subcommand_from verify" -s v -l verbose -d "Verbose output"
        complete -c jpegls -f -n "__fish_seen_subcommand_from verify" -s q -l quiet -d "Quiet mode"
        
        # batch command
        complete -c jpegls -f -n "__fish_seen_subcommand_from batch; and not __fish_seen_subcommand_from encode decode info verify" -a "encode decode info verify" -d "Batch operation"
        complete -c jpegls -f -n "__fish_seen_subcommand_from batch" -s o -l output-dir -d "Output directory" -r -a "(__fish_complete_directories)"
        complete -c jpegls -f -n "__fish_seen_subcommand_from batch" -s w -l width -d "Image width" -r
        complete -c jpegls -f -n "__fish_seen_subcommand_from batch" -s h -l height -d "Image height" -r
        complete -c jpegls -f -n "__fish_seen_subcommand_from batch" -s b -l bits-per-sample -d "Bits per sample" -r
        complete -c jpegls -f -n "__fish_seen_subcommand_from batch" -s c -l components -d "Component count" -r
        complete -c jpegls -f -n "__fish_seen_subcommand_from batch" -l near -d "NEAR parameter" -r
        complete -c jpegls -f -n "__fish_seen_subcommand_from batch" -l interleave -d "Interleave mode" -r -a "none line sample"
        complete -c jpegls -f -n "__fish_seen_subcommand_from batch" -l color-transform -d "Colour transform (American spelling)" -r -a "none hp1 hp2 hp3"
        complete -c jpegls -f -n "__fish_seen_subcommand_from batch" -l colour-transform -d "Colour transform (British spelling)" -r -a "none hp1 hp2 hp3"
        complete -c jpegls -f -n "__fish_seen_subcommand_from batch" -s p -l parallelism -d "Parallelism" -r
        complete -c jpegls -f -n "__fish_seen_subcommand_from batch" -l summarise -d "Print summary (British spelling)"
        complete -c jpegls -f -n "__fish_seen_subcommand_from batch" -l summarize -d "Print summary (American spelling)"
        complete -c jpegls -f -n "__fish_seen_subcommand_from batch" -l no-colour -d "Disable ANSI colour (British spelling)"
        complete -c jpegls -f -n "__fish_seen_subcommand_from batch" -l no-color -d "Disable ANSI colour (American spelling)"
        complete -c jpegls -f -n "__fish_seen_subcommand_from batch" -s v -l verbose -d "Verbose output"
        complete -c jpegls -f -n "__fish_seen_subcommand_from batch" -s q -l quiet -d "Quiet mode"
        complete -c jpegls -f -n "__fish_seen_subcommand_from batch" -l fail-fast -d "Stop on first error"
        
        # compare command
        complete -c jpegls -f -n "__fish_seen_subcommand_from compare" -l near -d "Pixel error tolerance" -r
        complete -c jpegls -f -n "__fish_seen_subcommand_from compare" -l json -d "JSON output"
        complete -c jpegls -f -n "__fish_seen_subcommand_from compare" -l no-colour -d "Disable ANSI colour (British spelling)"
        complete -c jpegls -f -n "__fish_seen_subcommand_from compare" -l no-color -d "Disable ANSI colour (American spelling)"
        complete -c jpegls -f -n "__fish_seen_subcommand_from compare" -s v -l verbose -d "Verbose output"
        complete -c jpegls -f -n "__fish_seen_subcommand_from compare" -s q -l quiet -d "Quiet mode"
        
        # completion command
        complete -c jpegls -f -n "__fish_seen_subcommand_from completion" -a "bash zsh fish" -d "Shell type"
        """
    }
}
