class NpAppwatch < Formula
  desc "Switches the NP Band Remote dongle's gesture profile with the app in front"
  homepage "https://github.com/Shlok-Bhakta/homebrew-np"
  url "https://github.com/Shlok-Bhakta/homebrew-np/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "614754ca0b690a46fd4d9ea2d12e745aa2c7d9d8bb90658ef7a4d0a62dfc5ac4"
  license "MIT"
  head "https://github.com/Shlok-Bhakta/homebrew-np.git", branch: "main"

  depends_on :macos

  def install
    system "swift", "build", "--disable-sandbox", "-c", "release"
    bin.install ".build/release/np-appwatch"
  end

  service do
    run [opt_bin/"np-appwatch"]
    keep_alive true
    process_type :interactive
    log_path var/"log/np-appwatch.log"
    error_log_path var/"log/np-appwatch.log"
  end

  def caveats
    <<~EOS
      Start it now and at every login:
        brew services start np-appwatch
      macOS asks once to let np-appwatch use Bluetooth: allow it.
      Profiles pick apps by bundle id ("apps" in the dongle's profile file); `np-appwatch front`
      prints the front app's.
    EOS
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/np-appwatch --version")
  end
end
