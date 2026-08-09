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
      },
    },
  },
  plugins: [],
}
