/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{js,jsx}'],
  theme: {
    extend: {
      colors: {
        primary: '#3D1152',
        secondary: '#1B4080',
        emergency: '#E53935',
        success: '#2E7D32',
        warning: '#FF8F00',

        // Landing-page palette.
        //
        // The reference pairs a warm cream ground with near-black ink and
        // colour-blocked cards. Cream is kept warm rather than tinted purple:
        // a warm neutral makes the purple read richer, where a purple-tinted
        // grey just muddies into it.
        cream: {
          DEFAULT: '#F4F1EC',   // the single page ground — no white anywhere
          deep: '#EBE6DE',      // pressed wells
          // Cards sit a shade *above* the ground rather than jumping to white.
          // Pure white against warm cream reads as two unrelated surfaces,
          // which is exactly the two-tone effect we are removing.
          card: '#FBF9F5',
        },
        ink: {
          DEFAULT: '#1C0A26',   // headings — purple-black, not pure black
          soft: '#4A3B55',      // body copy
          mute: '#8B7F96',      // captions
        },
        // Colour-blocked card fills, echoing the reference's black / maroon /
        // steel-blue trio but built from eKonnect's own hues.
        block: {
          night: '#140A1B',
          plum: '#3D1152',
          steel: '#24485C',
          coral: '#FF4D5E',
        },
      },
      fontFamily: {
        // Outfit is the closest freely available match to the reference's
        // geometric sans: high x-height, tight apertures, heavy display weights.
        sans: ['Outfit', 'Inter', 'system-ui', 'sans-serif'],
      },
      letterSpacing: {
        tightest: '-0.035em',
      },
    },
  },
  plugins: [],
}
