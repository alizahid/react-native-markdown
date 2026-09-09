require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))

Pod::Spec.new do |s|
  s.name         = "JetMarkdown"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.homepage     = package["homepage"]
  s.license      = package["license"]
  s.authors      = package["author"]

  s.platforms    = { :ios => min_ios_version_supported }
  s.source       = { :git => "https://github.com/alizahid/react-native-jet-markdown.git", :tag => "v#{s.version}" }

  # Headers are deliberately NOT in source_files. Xcode's project-wide
  # header maps index every pod target's headers BY BASENAME, so adding
  # generically named headers (md4c.h, Parser.h) to the Pods project
  # shadows other pods' same-named headers in THEIR quoted includes —
  # react-native-enriched-markdown's forked md4c and unistyles' parser
  # both stopped compiling. Our own includes are file-relative or resolve
  # through the search paths below; the headers ship in the npm package
  # and stay on disk (RN pods integrate via :path, which never cleans).
  s.source_files = "ios/**/*.{m,mm,swift,cpp}",
                   "cpp/core/**/*.cpp",
                   "cpp/react/**/*.cpp",
                   "cpp/md4c/*.c"
  s.preserve_paths = "ios/**/*.h", "cpp/**/*.h"

  s.pod_target_xcconfig = {
    # The override directory must precede generated headers so the custom
    # component descriptor shadows the codegen default.
    "HEADER_SEARCH_PATHS" => '"$(PODS_TARGET_SRCROOT)/cpp/react/override" "$(PODS_TARGET_SRCROOT)/cpp"',
    "CLANG_CXX_LANGUAGE_STANDARD" => "c++20",
  }

  # Image pipeline (same core expo-image uses): animated GIF/APNG with lazy
  # frame decoding, memory + disk caches, request dedupe and cancellation.
  s.dependency "SDWebImage", "~> 5.21"

  install_modules_dependencies(s)
end
