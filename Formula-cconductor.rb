# This file should be placed in a homebrew-cconductor tap repository
# at: Formula/cconductor.rb
#
# Repository: https://github.com/yaniv-golan/homebrew-cconductor
# Usage: brew tap yaniv-golan/cconductor && brew install cconductor

class Cconductor < Formula
  desc "AI Research, Orchestrated - Multi-agent research system powered by Claude"
  homepage "https://github.com/yaniv-golan/cconductor"
  url "https://github.com/yaniv-golan/cconductor/archive/v0.4.0.tar.gz"
  sha256 "" # Will be filled during release
  license "MIT"
  
  head "https://github.com/yaniv-golan/cconductor.git", branch: "main"

  depends_on "bash" => :build
  depends_on "jq"
  depends_on "curl"
  depends_on "bc"
  depends_on "ripgrep" => :recommended
  depends_on "node" => :recommended # For Claude Code CLI

  def install
    # Install all files to prefix
    prefix.install "cconductor"
    prefix.install "src"
    prefix.install "config"
    prefix.install "knowledge-base"
    prefix.install "docs"
    
    # Install library directory if it exists, otherwise create it
    if File.directory?("library")
      prefix.install "library"
    else
      (prefix/"library").mkpath
    end
    
    # Install supporting files
    prefix.install "VERSION"
    prefix.install "LICENSE"
    prefix.install "README.md"
    
    # Make all shell scripts executable
    system "chmod", "+x", "#{prefix}/cconductor"
    system "find", "#{prefix}", "-name", "*.sh", "-type", "f", "-exec", "chmod", "+x", "{}", "+"
    
    # Create library subdirectories if they don't exist
    (prefix/"library/sources").mkpath
    (prefix/"library/digests").mkpath
    
    # Create a wrapper script in bin that sets CCONDUCTOR_ROOT
    (bin/"cconductor").write <<~EOS
      #!/bin/bash
      export CCONDUCTOR_ROOT="#{prefix}"
      exec "#{prefix}/cconductor" "$@"
    EOS
    system "chmod", "+x", "#{bin}/cconductor"
  end

  def caveats
    <<~EOS
      CConductor requires Claude Code CLI to function.
      
      Install Claude Code CLI:
        npm install -g @anthropic-ai/claude-code
      
      Set up authentication:
        mkdir -p ~/.config/claude
        echo '{"api_key": "your_key"}' > ~/.config/claude/config.json
      
      Quick start:
        cconductor "What is quantum computing?"
      
      Documentation:
        #{prefix}/README.md
        https://github.com/yaniv-golan/cconductor
    EOS
  end

  test do
    assert_match "CConductor v#{version}", shell_output("#{bin}/cconductor --version")
  end
end
