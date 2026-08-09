import { initializeApp } from 'firebase/app'
import { getAuth } from 'firebase/auth'
import { getFirestore } from 'firebase/firestore'
import { getDatabase } from 'firebase/database'

const firebaseConfig = {
  apiKey: 'AIzaSyDwUvaCqXQo0Pxduziir63SiLIIqvhrxso',
  authDomain: 'ekonnectapp.firebaseapp.com',
  projectId: 'ekonnectapp',
  storageBucket: 'ekonnectapp.firebasestorage.app',
  messagingSenderId: '365887153225',
  appId: '1:365887153225:web:70ee612c9024a60cc90b98',
  measurementId: 'G-S1N2K1YVK0',
  // Replace with your actual Realtime Database URL from Firebase Console
  databaseURL: 'https://ekonnectapp-default-rtdb.firebaseio.com',
}

const app = initializeApp(firebaseConfig)
export const auth = getAuth(app)
export const db = getFirestore(app)
export const rtdb = getDatabase(app)
