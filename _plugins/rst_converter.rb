require 'open3'
require 'cgi'

module Jekyll
  # Converts reStructuredText (.rst) files to HTML.
  # Tries pandoc first, falls back to Python docutils.
  #
  # Local dev:  brew install pandoc
  # CI/CD:      pip install docutils  (then add to build command before jekyll build)
  class RstConverter < Converter
    safe true
    priority :low

    def matches(ext)
      ext =~ /^\.rst$/i
    end

    def output_ext(_ext)
      '.html'
    end

    def convert(content)
      if pandoc_available?
        convert_with_pandoc(content)
      elsif docutils_available?
        convert_with_docutils(content)
      else
        Jekyll.logger.warn 'RstConverter:', \
          'No RST converter found. Install pandoc (brew install pandoc) or ' \
          'Python docutils (pip install docutils). Rendering raw RST text.'
        "<pre>#{CGI.escapeHTML(content)}</pre>"
      end
    end

    private

    def pandoc_available?
      return @pandoc_available unless @pandoc_available.nil?
      @pandoc_available = system('pandoc --version > /dev/null 2>&1')
    end

    def docutils_available?
      return @docutils_available unless @docutils_available.nil?
      @docutils_available = system('python3 -c "import docutils" > /dev/null 2>&1')
    end

    def convert_with_pandoc(content)
      output, error, status = Open3.capture3(
        'pandoc -f rst -t html --no-highlight',
        stdin_data: content
      )
      if status.success?
        output
      else
        Jekyll.logger.warn 'RstConverter:', "pandoc error: #{error}"
        "<pre>#{CGI.escapeHTML(content)}</pre>"
      end
    end

    def convert_with_docutils(content)
      # python3 -m docutils reads RST from stdin and writes a full HTML document
      output, error, status = Open3.capture3(
        'python3 -m docutils --writer=html5 --no-doc-title --no-doc-info -',
        stdin_data: content
      )
      unless status.success?
        Jekyll.logger.warn 'RstConverter:', "docutils error: #{error}"
        return "<pre>#{CGI.escapeHTML(content)}</pre>"
      end
      # docutils outputs a full HTML page; extract only the <body> content
      output[/<body[^>]*>(.*?)<\/body>/m, 1] || output
    end
  end
end
