class AvrGccAT8 < Formula
  desc "GNU compiler collection for AVR 8-bit and 32-bit Microcontrollers"
  homepage "https://www.gnu.org/software/gcc/gcc.html"

  url "https://ftp.gnu.org/gnu/gcc/gcc-8.3.0/gcc-8.3.0.tar.xz"
  mirror "https://ftpmirror.gnu.org/gcc/gcc-8.3.0/gcc-8.3.0.tar.xz"
  sha256 "64baadfe6cc0f4947a84cb12d7f0dfaf45bb58b7e92461639596c21e02d97d2c"

  head "https://github.com/gcc-mirror/gcc.git", :branch => "gcc-8-branch"

  bottle do
    root_url "https://dl.bintray.com/osx-cross/bottles-avr"
    sha256 "035b5dd9f8d39555125b1a78b6b1e60e149aa3ffadb4edb2e42c2fd19a38a066" => :mojave
    sha256 "0a90ef4f20db1508118235824786ef60476c1d96eb2b641f9f8f94ccd6857565" => :high_sierra
  end

  # The bottles are built on systems with the CLT installed, and do not work
  # out of the box on Xcode-only systems due to an incorrect sysroot.
  pour_bottle? do
    reason "The bottle needs the Xcode CLT to be installed."
    satisfy { MacOS::CLT.installed? }
  end

  keg_only "it might interfere with other version of avr-gcc. This is useful if you want to have multiple version of avr-gcc installed on the same machine"

  option "with-ATMega168pbSupport", "Add ATMega168pb Support to avr-gcc"

  depends_on "autoconf" => :build
  depends_on "automake" => :build

  depends_on "avr-binutils"

  depends_on "gmp"
  depends_on "isl"
  depends_on "libmpc"
  depends_on "mpfr"

  # GCC bootstraps itself, so it is OK to have an incompatible C++ stdlib
  cxxstdlib_check :skip

  local_build = build

  resource "avr-libc" do
    url "https://download.savannah.gnu.org/releases/avr-libc/avr-libc-2.0.0.tar.bz2"
    mirror "https://download-mirror.savannah.gnu.org/releases/avr-libc/avr-libc-2.0.0.tar.bz2"
    sha256 "b2dd7fd2eefd8d8646ef6a325f6f0665537e2f604ed02828ced748d49dc85b97"

    if local_build.with? "ATMega168pbSupport"
      patch do
        url "https://dl.bintray.com/osx-cross/avr-patches/avr-libc-2.0.0-atmega168pb.patch"
        sha256 "7a2bf2e11cfd9335e8e143eecb94480b4871e8e1ac54392c2ee2d89010b43711"
      end
    end
  end

  def version_suffix
    if build.head?
      (stable.version.to_s.slice(/\d/).to_i + 1).to_s
    else
      version.to_s.slice(/\d/)
    end
  end

  def install
    # GCC will suffer build errors if forced to use a particular linker.
    ENV.delete "LD"
    ENV["gcc_cv_prog_makeinfo_modern"] = "no" # pretend that make info is too old to build documentation and avoid errors

    languages = ["c", "c++"]

    args = [
      "--target=avr",
      "--prefix=#{prefix}",
      "--libdir=#{lib}/avr-gcc/#{version_suffix}",

      "--enable-languages=#{languages.join(",")}",
      "--with-ld=#{Formula["avr-binutils"].opt_bin/"avr-ld"}",
      "--with-as=#{Formula["avr-binutils"].opt_bin/"avr-as"}",

      "--disable-nls",
      "--disable-libssp",
      "--disable-shared",
      "--disable-threads",
      "--disable-libgomp",
      "--with-dwarf2",
    ]

    mkdir "build" do
      system "../configure", *args
      system "make"

      system "make", "install"
    end

    # info and man7 files conflict with native gcc
    info.rmtree
    man7.rmtree

    local_build = build

    resource("avr-libc").stage do
      ENV.prepend_path "PATH", bin

      ENV.delete "CFLAGS"
      ENV.delete "CXXFLAGS"
      ENV.delete "LD"
      ENV.delete "CC"
      ENV.delete "CXX"

      build = `./config.guess`.chomp

      system "./bootstrap" if local_build.with? "ATMega168pbSupport"
      system "./configure", "--build=#{build}", "--prefix=#{prefix}", "--host=avr"
      system "make", "install"
    end
  end

  test do
    ENV.clear

    hello_c = <<~EOS
      #define F_CPU 8000000UL

      #include <avr/io.h>
      #include <util/delay.h>

      int main (void) {

        DDRB |= (1 << PB0);

        while(1) {
          PORTB ^= (1 << PB0);
          _delay_ms(500);
        }

        return 0;
      }
    EOS

    hello_c_hex = <<~EOS
      :10000000209A91E085B1892785B92FEF34E38CE000
      :0E001000215030408040E1F700C00000F3CFE7
      :00000001FF
    EOS

    hello_c_hex.gsub!(/\n/, "\r\n")

    (testpath/"hello.c").write(hello_c)

    system "#{bin}/avr-gcc", "-mmcu=atmega328p", "-Os", "-c", "hello.c", "-o", "hello.c.o", "--verbose"
    system "#{bin}/avr-gcc", "hello.c.o", "-o", "hello.c.elf"
    system "avr-objcopy", "-O", "ihex", "-j", ".text", "-j", ".data", "hello.c.elf", "hello.c.hex"

    assert_equal `cat hello.c.hex`, hello_c_hex

    hello_cpp = <<~EOS
      #define F_CPU 8000000UL

      #include <avr/io.h>
      #include <util/delay.h>

      int main (void) {

        DDRB |= (1 << PB0);

        uint8_t array[] = {1, 2, 3, 4};

        for (auto n : array) {
          uint8_t m = n;
          while (m > 0) {
            _delay_ms(500);
            PORTB ^= (1 << PB0);
            m--;
          }
        }

        return 0;
      }
    EOS

    hello_cpp_hex = <<~EOS
      :1000000010E0A0E6B0E0ECE7F0E003C0C895319660
      :100010000D92A436B107D1F700D000D0CDB7DEB72E
      :10002000209A8091600090916100A0916200B0914F
      :10003000630089839A83AB83BC83FE0131969E0162
      :100040002B5F3F4F41E08191882371F05FEF64E3C4
      :100050009CE0515060409040E1F700C0000095B135
      :10006000942795B98150F0CFE217F30761F790E03C
      :0C00700080E00F900F900F900F9008950B
      :04007C000102030476
      :00000001FF
    EOS

    hello_cpp_hex.gsub!(/\n/, "\r\n")

    (testpath/"hello.cpp").write(hello_cpp)

    system "#{bin}/avr-g++", "-mmcu=atmega328p", "-Os", "-c", "hello.cpp", "-o", "hello.cpp.o", "--verbose"
    system "#{bin}/avr-g++", "hello.cpp.o", "-o", "hello.cpp.elf"
    system "avr-objcopy", "-O", "ihex", "-j", ".text", "-j", ".data", "hello.cpp.elf", "hello.cpp.hex"

    assert_equal `cat hello.cpp.hex`, hello_cpp_hex
  end
end
